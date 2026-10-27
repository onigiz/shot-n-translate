import Foundation
import NaturalLanguage

public enum LanguageDetector {
    private static let minimumHypothesisConfidence: Double = 0.08

    /// Returns a BCP 47 language code such as `en` or `tr`, or nil when the text has no clear language.
    public static func detectCode(in text: String, visionHints: [String] = []) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let script = scriptLanguage(in: trimmed) {
            return script
        }

        if let natural = naturalLanguageCode(in: trimmed) {
            return natural
        }

        if let hint = visionHints.first(where: { !$0.isEmpty }) {
            return baseCode(hint)
        }

        return latinFallback(in: trimmed)
    }

    public static func matches(_ code: String, target: TranslationTarget) -> Bool {
        baseCode(code) == target.rawValue
    }

    public static func baseCode(_ code: String) -> String {
        code.split(separator: "-").first.map(String.init)?.lowercased() ?? code.lowercased()
    }

    private static func naturalLanguageCode(in text: String) -> String? {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = [
            .english: 0.5,
            .turkish: 0.5,
            .german: 0.2,
            .french: 0.2,
            .spanish: 0.2,
            .italian: 0.15,
            .portuguese: 0.15,
            .dutch: 0.1,
            .russian: 0.2,
            .arabic: 0.15,
            .japanese: 0.15,
            .korean: 0.15,
            .simplifiedChinese: 0.15,
            .traditionalChinese: 0.15
        ]
        recognizer.processString(compact)

        if let language = recognizer.dominantLanguage, language != .undetermined {
            return language.rawValue
        }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        let best = hypotheses
            .filter { $0.key != .undetermined && $0.value >= minimumHypothesisConfidence }
            .max(by: { $0.value < $1.value })
        return best?.key.rawValue
    }

    private static func scriptLanguage(in text: String) -> String? {
        var turkishMarks = 0
        var hangul = 0
        var hiraganaKatakana = 0
        var han = 0
        var cyrillic = 0
        var arabic = 0
        var greek = 0
        var hebrew = 0
        var latinLetters = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x011E, 0x011F, 0x0130, 0x0131, 0x015E, 0x015F, 0x00C7, 0x00E7,
                 0x00D6, 0x00F6, 0x00DC, 0x00FC:
                // Ğğ İ ı Şş Çç Öö Üü — strong Turkish signal among Latin text.
                turkishMarks += 1
                latinLetters += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latinLetters += 1
            case 0xAC00...0xD7A3:
                hangul += 1
            case 0x3040...0x30FF:
                hiraganaKatakana += 1
            case 0x4E00...0x9FFF:
                han += 1
            case 0x0400...0x04FF:
                cyrillic += 1
            case 0x0600...0x06FF:
                arabic += 1
            case 0x0370...0x03FF:
                greek += 1
            case 0x0590...0x05FF:
                hebrew += 1
            default:
                break
            }
        }

        if hangul > 0 { return "ko" }
        if hiraganaKatakana > 0 { return "ja" }
        if han > 0 && hiraganaKatakana == 0 && hangul == 0 { return "zh" }
        if cyrillic >= 3 { return "ru" }
        if arabic >= 3 { return "ar" }
        if greek >= 3 { return "el" }
        if hebrew >= 3 { return "he" }
        if turkishMarks > 0 { return "tr" }
        return nil
    }

    /// Short all-Latin OCR snippets often leave NL undetermined.
    /// Prefer English when the fragment looks like plain Latin words without Turkish marks.
    private static func latinFallback(in text: String) -> String? {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 12 else { return nil }
        let nonLatin = letters.contains { scalar in
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A:
                false
            case 0x00C0...0x024F, 0x1E00...0x1EFF:
                // Extended Latin; leave undecided unless already caught by script heuristics.
                true
            default:
                true
            }
        }
        if nonLatin { return nil }
        let wordLike = text.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil
        return wordLike ? "en" : nil
    }
}
