import Foundation

public struct CaptureTranslation: Equatable, Sendable {
    public enum Note: Equatable, Sendable {
        case alreadyInTargetLanguage
        case languageNotDetected
        case translationUnavailable
    }

    public var original: String
    public var sourceLanguageCode: String?
    public var translatedText: String?
    public var note: Note?

    public init(
        original: String,
        sourceLanguageCode: String?,
        translatedText: String?,
        note: Note? = nil
    ) {
        self.original = original
        self.sourceLanguageCode = sourceLanguageCode
        self.translatedText = translatedText
        self.note = note
    }

    /// The text shown under the screenshot and written into the PDF.
    /// A capture already in the target language uses that text as the translation.
    public var textForPreview: String? {
        if let translatedText {
            let cleaned = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        if note == .alreadyInTargetLanguage {
            let cleaned = original.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }
}
