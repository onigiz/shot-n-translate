import AppKit
import CoreGraphics
import Observation
import ShotNTranslateCore
import UniformTypeIdentifiers
@preconcurrency import Translation

@MainActor
@Observable
final class ScreenshotTranslator {
    enum Presentation: Equatable {
        case idle
        case working
        case failure(L10nKey)
        case result(CaptureTranslation)
    }

    private(set) var isBusy = false
    private(set) var isTranslating = false
    private(set) var presentation: Presentation = .idle
    private(set) var translationConfiguration: TranslationSession.Configuration?
    private(set) var capturePreview: NSImage?
    /// Clockwise turn of the preview and the PDF. The stored capture stays as shot.
    private(set) var previewTurn = PreviewImageTurn(clockwiseDegrees: 0)
    private(set) var previewMarkup = PreviewMarkup()
    private(set) var previewTool: PreviewCanvasTool = .rotate
    private(set) var shapeRed = 0.86
    private(set) var shapeGreen = 0.15
    private(set) var shapeBlue = 0.15
    /// 1...12. The outline grows with this setting.
    private(set) var shapeThickness = 4.0
    private(set) var saveNotice: L10nKey?
    private(set) var draft = NSAttributedString()
    private(set) var draftToken = UUID()
    private(set) var editorIsDark = false
    /// Full-resolution capture kept until the preview window closes.
    private var capturedImage: CGImage?
    private var pendingText: String?
    private var session = UUID()
    private var translationID = UUID()
    private var translationWork: Task<Void, Never>?
    private var translationWatchdog: Task<Void, Never>?
    /// Menu-bar apps do not present the system language download. Raise the
    /// app only while that download can still be requested.
    private var activationRaisedForDownload = false

    var currentTranslationID: UUID { translationID }
    private var draftWasSeeded = false
    let editing = TranslationEditingController()

    private let settings: TranslationSettings
    private let languageStore: LanguageStore

    init(settings: TranslationSettings, languageStore: LanguageStore) {
        self.settings = settings
        self.languageStore = languageStore
        editing.onChange = { [weak self] text in
            self?.draft = text
        }
    }

    var canSaveFormattedPDF: Bool {
        !isTranslating && !draft.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setEditorSurface(isDark: Bool) {
        guard editorIsDark != isDark else { return }
        editorIsDark = isDark
    }

    func translateSelection() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let instruction = L10n.string(.dragToSelect, language: languageStore.language)
        let selector = RegionSelector()
        guard let rect = await selector.select(instruction: instruction) else { return }
        TranslationResultWindow.hideWithoutReleasing()
        let session = beginSession()
        // The selection shade is full-screen. Capturing before it leaves the
        // compositor produces a black rectangle where the page was.
        do {
            try await Task.sleep(nanoseconds: 550_000_000)
        } catch {
            return
        }
        guard isCurrent(session) else { return }

        let prepared: CGImage
        do {
            // Capture before the result window is shown, so the window cannot cover the selection.
            let captured = try await ScreenRegionCapture.image(forAppKitRect: rect)
            prepared = TextRecognizer.standardImage(captured)
        } catch {
            guard isCurrent(session) else { return }
            presentation = .failure(ScreenRegionCapture.permissionDenied(error) ? .screenRecordingDenied : .captureFailed)
            TranslationResultWindow.show(translator: self, languageStore: languageStore)
            return
        }
        guard isCurrent(session) else { return }

        showPreview(prepared)
        let region: CGRect
        if settings.scope == .regionFirst {
            guard let chosen = await chooseRegion(on: prepared) else {
                guard isCurrent(session) else { return }
                releasePreview()
                return
            }
            guard isCurrent(session) else { return }
            region = chosen
        } else {
            region = ImageRegionGeometry.fullRect(width: prepared.width, height: prepared.height)
        }
        await recognizeAndPresent(fullImage: prepared, region: region, session: session)
    }

    /// Reads a region of the current screenshot again and replaces the editor text.
    /// The stored screenshot stays whole.
    func retranslateSelectedRegion() async {
        guard !isBusy, !isTranslating, let image = capturedImage else { return }
        isBusy = true
        defer { isBusy = false }
        let session = self.session
        guard let region = await chooseRegion(on: image) else { return }
        guard isCurrent(session), capturedImage != nil else { return }
        await recognizeAndPresent(fullImage: image, region: region, session: session)
    }

    private func chooseRegion(on image: CGImage) async -> CGRect? {
        let language = languageStore.language
        return await ImageRegionPicker(image: image).select(
            instruction: L10n.string(.dragTranslationArea, language: language),
            confirmTitle: L10n.string(.translateSelectedArea, language: language),
            cancelTitle: L10n.string(.cancel, language: language),
            windowTitle: L10n.string(.translationAreaTitle, language: language)
        )
    }

    private func recognizeAndPresent(fullImage: CGImage, region: CGRect, session: UUID) async {
        guard isCurrent(session) else { return }
        presentation = .working
        TranslationResultWindow.show(translator: self, languageStore: languageStore)
        let recognitionSource = ImageRegionCrop.recognitionImage(from: fullImage, pixelRect: region)
        let recognized: RecognizedText?
        do {
            recognized = try await readableText(in: recognitionSource)
        } catch {
            guard isCurrent(session) else { return }
            presentation = .failure(.recognitionFailed)
            return
        }
        guard isCurrent(session) else { return }
        if let recognized {
            presentRecognizedText(recognized)
            return
        }
        presentation = .failure(.noTextFound)
    }

    /// Drops the in-memory capture. Closing the window does not write a PDF.
    func releasePreview() {
        _ = beginSession()
        presentation = .idle
    }

    func savePDF() {
        guard canSaveFormattedPDF, let image = capturedImage else { return }
        let document = NSAttributedString(attributedString: draft)
        let darkBackground = editorIsDark
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = L10n.string(.pdfFileName, language: languageStore.language)
        NSApp.activate()
        panel.begin { [weak self] response in
            guard let self else { return }
            let destination = panel.url
            Task { @MainActor in
                guard response == .OK, let destination else { return }
                do {
                    let marked = PreviewMarkupImage.image(from: image, markup: self.previewMarkup)
                    let turned = self.previewTurn.image(from: marked)
                    try TranslationPreviewPDF.write(
                        image: turned,
                        document: document,
                        darkBackground: darkBackground,
                        to: destination
                    )
                    self.saveNotice = .pdfSaved
                } catch {
                    self.saveNotice = .pdfSaveFailed
                }
            }
        }
    }

    private func readableText(in image: CGImage) async throws -> RecognizedText? {
        let recognized = try await TextRecognizer.recognize(in: image)
        guard !recognized.text.isEmpty else { return nil }
        return recognized
    }

    private func beginSession() -> UUID {
        let id = UUID()
        session = id
        cancelTranslationWait()
        restoreMenuBarActivation()
        pendingText = nil
        translationConfiguration = nil
        isTranslating = false
        capturePreview = nil
        capturedImage = nil
        previewTurn = PreviewImageTurn(clockwiseDegrees: 0)
        previewMarkup = PreviewMarkup()
        previewTool = .rotate
        saveNotice = nil
        draft = NSAttributedString()
        draftToken = UUID()
        draftWasSeeded = false
        translationID = UUID()
        presentation = .idle
        return id
    }

    private func isCurrent(_ id: UUID) -> Bool {
        session == id
    }

    func setPreviewClockwiseDegrees(_ degrees: Double) {
        let turn = PreviewImageTurn(clockwiseDegrees: degrees)
        guard capturedImage != nil, turn != previewTurn else { return }
        previewTurn = turn
    }

    func selectPreviewTool(_ tool: PreviewCanvasTool) {
        previewTool = previewTool == tool ? .rotate : tool
    }

    func setShapeColor(red: Double, green: Double, blue: Double) {
        shapeRed = red
        shapeGreen = green
        shapeBlue = blue
    }

    func setShapeThickness(_ thickness: Double) {
        shapeThickness = min(max(thickness, 1), 12)
    }

    func addPreviewMark(visibleBounds: CGRect, kind: PreviewMarkKind) {
        guard let image = capturedImage else { return }
        guard visibleBounds.width >= 0.02, visibleBounds.height >= 0.02 else { return }
        let original = PreviewMarkupGeometry.originalBounds(visibleBounds, crop: previewMarkup.crop)
        let shorter = min(
            previewMarkup.crop.width * Double(image.width),
            previewMarkup.crop.height * Double(image.height)
        )
        previewMarkup.marks.append(PreviewMark(
            kind: kind,
            bounds: original,
            red: shapeRed,
            green: shapeGreen,
            blue: shapeBlue,
            strokePixels: PreviewMarkup.strokeWidth(thickness: shapeThickness, shorterSide: shorter)
        ))
        refreshPreview()
    }

    func cropPreview(toVisible visible: CGRect) {
        guard capturedImage != nil else { return }
        guard visible.width >= 0.04, visible.height >= 0.04 else { return }
        let next = PreviewMarkupGeometry.crop(previewMarkup.crop, toVisible: visible)
        guard next.width >= 0.02, next.height >= 0.02 else { return }
        previewMarkup.crop = next
        refreshPreview()
    }

    func resetPreviewCrop() {
        guard previewMarkup.isCropped else { return }
        previewMarkup.crop = PreviewMarkup.wholeImage
        refreshPreview()
    }

    func undoPreviewMark() {
        guard !previewMarkup.marks.isEmpty else { return }
        previewMarkup.marks.removeLast()
        refreshPreview()
    }

    private func refreshPreview() {
        guard let image = capturedImage else { return }
        capturePreview = fittedPreview(of: PreviewMarkupImage.image(from: image, markup: previewMarkup))
    }

    private func showPreview(_ image: CGImage) {
        capturedImage = image
        previewTurn = PreviewImageTurn(clockwiseDegrees: 0)
        capturePreview = fittedPreview(of: image)
    }

    private func fittedPreview(of image: CGImage) -> NSImage {
        let pixelWidth = CGFloat(max(image.width, 1))
        let pixelHeight = CGFloat(max(image.height, 1))
        let longest = max(pixelWidth, pixelHeight)
        let fitted = min(1, 720 / longest)
        return NSImage(
            cgImage: image,
            size: NSSize(width: pixelWidth * fitted, height: pixelHeight * fitted)
        )
    }

    private func presentRecognizedText(_ recognized: RecognizedText) {
        let text = TranslationText.prepare(recognized.text)
        guard !text.isEmpty else {
            presentation = .failure(.noTextFound)
            return
        }

        let detection = LanguageDetector.detect(in: text, visionHints: recognized.visionLanguageCodes)
        let code = detection.code
        let source = detection.isConfident ? code : nil
        startTranslation(of: text, source: source)
    }

    /// Translates again after the preview corrects the source language.
    func useSource(_ code: String) {
        guard case .result(let result) = presentation else { return }
        let base = LanguageDetector.baseCode(code)
        guard !base.isEmpty else { return }
        startTranslation(of: result.original, source: base)
    }

    func sourceChoices(selected: String?) -> [String] {
        var codes = LanguageDetector.correctionCodes
        if let selected {
            let base = LanguageDetector.baseCode(selected)
            if !base.isEmpty, !codes.contains(base) {
                codes.insert(base, at: 0)
            }
        }
        return codes
    }

    private func startTranslation(of text: String, source: String?) {
        draftWasSeeded = false
        cancelTranslationWait()
        translationID = UUID()
        translationConfiguration = nil
        if let source, LanguageDetector.matches(source, target: settings.target) {
            pendingText = nil
            isTranslating = false
            showResult(CaptureTranslation(
                original: text,
                sourceLanguageCode: source,
                translatedText: nil,
                note: .alreadyInTargetLanguage
            ))
            return
        }

        pendingText = text
        isTranslating = true
        showResult(CaptureTranslation(
            original: text,
            sourceLanguageCode: source,
            translatedText: nil,
            note: source == nil ? .languageNotDetected : nil
        ))
        let generation = translationID
        let targetCode = settings.target.rawValue
        translationWork = Task { @MainActor in
            let paragraphs = Self.paragraphsReady(for: text)
            guard !paragraphs.isEmpty else {
                finishTranslation(of: text, generation: generation, translated: nil, detectedSourceCode: nil)
                return
            }
            if let source, await InstalledTranslation.isInstalled(source: source, target: targetCode) {
                let outcome = await InstalledTranslation.translate(
                    paragraphs: paragraphs,
                    sourceCode: source,
                    targetCode: targetCode
                )
                guard !Task.isCancelled else { return }
                finishTranslation(
                    of: text,
                    generation: generation,
                    translated: outcome?.text,
                    detectedSourceCode: outcome?.sourceCode
                )
                return
            }
            guard !Task.isCancelled else { return }
            allowTranslationDownloadPrompt()
            var configuration = TranslationSession.Configuration(
                source: source.map { Locale.Language(identifier: $0) },
                target: Locale.Language(identifier: targetCode)
            )
            configuration.invalidate()
            translationConfiguration = configuration
        }
        translationWatchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: InstalledTranslation.answerLimit)
            guard !Task.isCancelled else { return }
            InstalledTranslation.cancelActive()
            finishTranslation(of: text, generation: generation, translated: nil, detectedSourceCode: nil)
        }
    }

    private static func paragraphsReady(for text: String) -> [String] {
        TranslationText.paragraphs(in: TranslationText.prepare(text))
            .map { LanguageDetector.textForTranslation($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func cancelTranslationWait() {
        translationWork?.cancel()
        translationWork = nil
        translationWatchdog?.cancel()
        translationWatchdog = nil
        InstalledTranslation.cancelActive()
    }

    /// A menu-bar app cannot show the system language sheet. Become a normal
    /// app only until that request finishes, then return to the menu bar.
    private func allowTranslationDownloadPrompt() {
        guard !activationRaisedForDownload else { return }
        activationRaisedForDownload = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    private func restoreMenuBarActivation() {
        guard activationRaisedForDownload else { return }
        activationRaisedForDownload = false
        NSApp.setActivationPolicy(.accessory)
    }

    func textWaitingForTranslation() -> String? {
        pendingText
    }

    func finishTranslation(
        of text: String,
        generation: UUID,
        translated: String?,
        detectedSourceCode: String?
    ) {
        guard translationID == generation, pendingText == text else { return }
        cancelTranslationWait()
        restoreMenuBarActivation()
        pendingText = nil
        replaceResult { result in
            if let detectedSourceCode, result.sourceLanguageCode == nil {
                let base = LanguageDetector.baseCode(detectedSourceCode)
                if !base.isEmpty, base != "und" {
                    result.sourceLanguageCode = base
                }
            }
            if let translated {
                let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    result.translatedText = cleaned
                    result.note = nil
                    return
                }
            }
            result.note = .translationUnavailable
        }
        isTranslating = false
    }

    private func replaceResult(_ update: (inout CaptureTranslation) -> Void) {
        guard case .result(var result) = presentation else { return }
        update(&result)
        showResult(result)
    }

    private func showResult(_ result: CaptureTranslation) {
        presentation = .result(result)
        guard !draftWasSeeded, let text = result.textForPreview else { return }
        draft = TranslationInk.plain(text, isDark: editorIsDark)
        draftToken = UUID()
        draftWasSeeded = true
    }
}
