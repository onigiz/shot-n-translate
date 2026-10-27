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

        presentation = .working
        TranslationResultWindow.show(translator: self, languageStore: languageStore)
        do {
            try await Task.sleep(nanoseconds: 120_000_000)
        } catch {
            return
        }

        let image: CGImage
        do {
            image = try await ScreenRegionCapture.image(in: rect)
        } catch {
            presentation = .failure(ScreenRegionCapture.permissionDenied(error) ? .screenRecordingDenied : .captureFailed)
            return
        }

        let text: String
        do {
            text = try TextRecognizer.recognize(in: image)
        } catch {
            presentation = .failure(.recognitionFailed)
            return
        }
        guard !text.isEmpty else {
            presentation = .failure(.noTextFound)
            return
        }

        guard let code = LanguageDetector.detectCode(in: text) else {
            presentation = .result(CaptureTranslation(
                original: text,
                sourceLanguageCode: nil,
                translatedText: nil,
                note: .languageNotDetected
            ))
            return
        }

        if LanguageDetector.matches(code, target: settings.target) {
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
            translatedText: nil
        ))
        var configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: code),
            target: Locale.Language(identifier: settings.target.rawValue)
        )
        configuration.invalidate()
        translationConfiguration = configuration
    }

    func textWaitingForTranslation() -> String? {
        pendingText
    }

    func finishTranslation(of text: String, translated: String?) {
        guard pendingText == text else { return }
        replaceResult { result in
            if let translated, !translated.isEmpty {
                result.translatedText = translated
                result.note = nil
            } else {
                result.note = .translationUnavailable
            }
        }
        isTranslating = false
    }

    private func replaceResult(_ update: (inout CaptureTranslation) -> Void) {
        guard case .result(var result) = presentation else { return }
        update(&result)
        presentation = .result(result)
    }
}
