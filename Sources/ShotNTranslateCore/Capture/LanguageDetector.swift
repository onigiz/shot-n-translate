import Foundation
import NaturalLanguage

public enum LanguageDetector {
    /// Returns a BCP 47 language code such as `en` or `tr`, or nil when the text has no clear language.
    public static func detectCode(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }

    public static func matches(_ code: String, target: TranslationTarget) -> Bool {
        let base = code.split(separator: "-").first.map(String.init)?.lowercased() ?? code.lowercased()
        return base == target.rawValue
    }
}
