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
        presentation = .working
        TranslationResultWindow.show(translator: self, languageStore: languageStore)

        let recognized: RecognizedText?
        do {
            recognized = try await readableText(in: prepared)
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

        let code = LanguageDetector.detectCode(in: text, visionHints: recognized.visionLanguageCodes)

        if let code, LanguageDetector.matches(code, target: settings.target) {
            pendingText = nil
            isTranslating = false
            translationConfiguration = nil
            showResult(CaptureTranslation(
                original: text,
                sourceLanguageCode: code,
                translatedText: nil,
                note: .alreadyInTargetLanguage
            ))
            return
        }

        pendingText = text
        isTranslating = true
        showResult(CaptureTranslation(
            original: text,
            sourceLanguageCode: code,
            translatedText: nil,
            note: code == nil ? .languageNotDetected : nil
        ))
        // Nil source lets Translation detect the language when OCR + NL disagree or stay undecided.
        var configuration = TranslationSession.Configuration(
            source: code.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: settings.target.rawValue)
        )
        configuration.invalidate()
        translationConfiguration = configuration
    }

    func textWaitingForTranslation() -> String? {
        pendingText
    }

    func finishTranslation(of text: String, translated: String?, detectedSourceCode: String?) {
        guard pendingText == text else { return }
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
