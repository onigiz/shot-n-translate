import AppKit
import CoreGraphics
import Observation
import ShotNTranslateCore
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
    private var pendingText: String?

    private let settings: TranslationSettings
    private let languageStore: LanguageStore

    init(settings: TranslationSettings, languageStore: LanguageStore) {
        self.settings = settings
        self.languageStore = languageStore
    }

    func translateSelection() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let instruction = L10n.string(.dragToSelect, language: languageStore.language)
        let selector = RegionSelector()
        guard let rect = await selector.select(instruction: instruction) else { return }

        capturePreview = nil
        pendingText = nil
        translationConfiguration = nil

        let prepared: CGImage
        do {
            // Capture before the result window is shown, so the window cannot cover the selection.
            let captured = try await ScreenRegionCapture.image(forAppKitRect: rect)
            prepared = TextRecognizer.standardImage(captured)
        } catch {
            presentation = .failure(ScreenRegionCapture.permissionDenied(error) ? .screenRecordingDenied : .captureFailed)
            TranslationResultWindow.show(translator: self, languageStore: languageStore)
            return
        }

        showPreview(prepared)
        presentation = .working
        TranslationResultWindow.show(translator: self, languageStore: languageStore)

        let recognized: RecognizedText?
        do {
            recognized = try readableText(in: prepared)
        } catch {
            presentation = .failure(.recognitionFailed)
            return
        }
        if let recognized {
            presentRecognizedText(recognized)
            return
        }
        presentation = .failure(.noTextFound)
    }

    private func readableText(in image: CGImage) throws -> RecognizedText? {
        let recognized = try TextRecognizer.recognize(in: image)
        guard !recognized.text.isEmpty else { return nil }
        return recognized
    }

    private func showPreview(_ image: CGImage) {
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
            presentation = .result(CaptureTranslation(
                original: text,
                sourceLanguageCode: code,
                translatedText: nil,
                note: .alreadyInTargetLanguage
            ))
            return
        }

        pendingText = text
        isTranslating = true
        presentation = .result(CaptureTranslation(
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
        presentation = .result(result)
    }
}
