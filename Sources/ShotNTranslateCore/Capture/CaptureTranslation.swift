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
}
