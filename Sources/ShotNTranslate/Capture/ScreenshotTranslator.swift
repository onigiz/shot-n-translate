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
    private(set) var saveNotice: L10nKey?
    private(set) var draft = NSAttributedString()
    private(set) var draftToken = UUID()
    private(set) var editorIsDark = false
    /// Full-resolution capture kept until the preview window closes.
    private var capturedImage: CGImage?
    private var pendingText: String?
    private var session = UUID()
    private var translationID = UUID()

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
                    try TranslationPreviewPDF.write(
                        image: image,
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
        pendingText = nil
        translationConfiguration = nil
        isTranslating = false
        capturePreview = nil
        capturedImage = nil
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

    private func showPreview(_ image: CGImage) {
        capturedImage = image
        let pixelWidth = CGFloat(max(image.width, 1))
        let pixelHeight = CGFloat(max(image.height, 1))
        let longest = max(pixelWidth, pixelHeight)
        let fitted = min(1, 720 / longest)
        capturePreview = NSImage(
            cgImage: image,
            size: NSSize(width: pixelWidth * fitted, height: pixelHeight * fitted)
        )
    }

    private func presentRecognizedText(_ recognized: RecognizedText) {
        let text = recognized.text

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
        translationID = UUID()
        if let source, LanguageDetector.matches(source, target: settings.target) {
            pendingText = nil
            isTranslating = false
            translationConfiguration = nil
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
        var configuration = TranslationSession.Configuration(
            source: source.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: settings.target.rawValue)
        )
        configuration.invalidate()
        translationConfiguration = configuration
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
