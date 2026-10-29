import Foundation
import NaturalLanguage

public struct LanguageDetection: Equatable, Sendable {
    public var code: String?
    /// Safe to pass to Translation as the source language.
    public var isConfident: Bool

    public init(code: String?, isConfident: Bool) {
        self.code = code
        self.isConfident = isConfident
    }
}

public enum LanguageDetector {
    /// Languages offered when the preview source is wrong.
    public static let correctionCodes = ["en", "tr", "de", "fr", "es", "it", "pt", "nl", "ru", "ar", "ja", "zh", "ko"]

    private static let confidentHypothesis: Double = 0.45
    private static let minimumHypothesisConfidence: Double = 0.2

    /// Returns a BCP 47 language code such as `en` or `tr`, or nil when the text has no clear language.
    public static func detectCode(in text: String, visionHints: [String] = []) -> String? {
        detect(in: text, visionHints: visionHints).code
    }

    /// Detects the source language and whether that code should be given to Translation.
    /// Latin text is not labeled Japanese, Chinese, or Korean because of one stray OCR character.
    public static func detect(in text: String, visionHints: [String] = []) -> LanguageDetection {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return LanguageDetection(code: nil, isConfident: false) }

        if let script = scriptLanguage(in: trimmed) {
            return LanguageDetection(code: script, isConfident: true)
        }

        if let natural = naturalLanguageCode(in: trimmed), allows(natural.code, in: trimmed) {
            let confident = natural.confidence >= confidentHypothesis
                || (isMostlyLatin(trimmed) && isLatinLanguage(natural.code))
            return LanguageDetection(code: natural.code, isConfident: confident)
        }

        if let hint = visionHints.first(where: { !$0.isEmpty }) {
            let code = baseCode(hint)
            if allows(code, in: trimmed) {
                return LanguageDetection(code: code, isConfident: false)
            }
        }

        let fallbackSource = isMostlyLatin(trimmed) ? withoutCJK(trimmed) : trimmed
        if let latin = latinFallback(in: fallbackSource) {
            return LanguageDetection(code: latin, isConfident: true)
        }
        return LanguageDetection(code: nil, isConfident: false)
    }

    private static func withoutCJK(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x4E00...0x9FFF, 0xAC00...0xD7A3:
                false
            default:
                true
            }
        })
    }

    public static func matches(_ code: String, target: TranslationTarget) -> Bool {
        baseCode(code) == target.rawValue
    }

    public static func baseCode(_ code: String) -> String {
        code.split(separator: "-").first.map(String.init)?.lowercased() ?? code.lowercased()
    }

    private static func naturalLanguageCode(in text: String) -> (code: String, confidence: Double)? {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        if isMostlyLatin(compact) {
            let latin: [NLLanguage] = [
                .english, .turkish, .german, .french, .spanish, .italian,
                .portuguese, .dutch, .polish, .swedish, .danish, .norwegian,
                .romanian, .czech, .hungarian, .finnish
            ]
            recognizer.languageConstraints = latin
            recognizer.languageHints = [
                .english: 0.6,
                .turkish: 0.45,
                .german: 0.15,
                .french: 0.15,
                .spanish: 0.15,
                .italian: 0.1,
                .portuguese: 0.1,
                .dutch: 0.1
            ]
        } else {
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
        }
        recognizer.processString(compact)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        guard let best = hypotheses
            .filter({ $0.key != .undetermined && $0.value >= minimumHypothesisConfidence })
            .max(by: { $0.value < $1.value }) else {
            return nil
        }
        return (best.key.rawValue, best.value)
    }

    private static func isLatinLanguage(_ code: String) -> Bool {
        switch baseCode(code) {
        case "en", "tr", "de", "fr", "es", "it", "pt", "nl", "pl", "sv", "da", "no", "nb", "ro", "cs", "hu", "fi":
            true
        default:
            false
        }
    }

    /// Latin letters overwhelm any CJK marks, so one bad OCR glyph cannot choose Japanese.
    private static func isMostlyLatin(_ text: String) -> Bool {
        let counts = scriptCounts(in: text)
        let cjk = counts.hangul + counts.kana + counts.han
        return counts.latin >= 8 && counts.latin > cjk * 4 && counts.cyrillic < 3 && counts.arabic < 3
    }

    private static func allows(_ code: String, in text: String) -> Bool {
        let counts = scriptCounts(in: text)
        let base = baseCode(code)
        if isMostlyLatin(text) {
            return isLatinLanguage(base)
        }
        switch base {
        case "ja":
            return counts.kana >= 3
        case "ko":
            return counts.hangul >= 2
        case "zh":
            return counts.han >= 2 && counts.kana == 0 && counts.hangul == 0
        case "ru":
            return counts.cyrillic >= 3
        case "ar":
            return counts.arabic >= 3
        case "el":
            return counts.greek >= 3
        case "he":
            return counts.hebrew >= 3
        default:
            return true
        }
    }

    private struct ScriptCounts {
        var turkishMarks = 0
        var hangul = 0
        var kana = 0
        var han = 0
        var cyrillic = 0
        var arabic = 0
        var greek = 0
        var hebrew = 0
        var latin = 0
    }

    private static func scriptCounts(in text: String) -> ScriptCounts {
        var counts = ScriptCounts()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x011E, 0x011F, 0x0130, 0x0131, 0x015E, 0x015F, 0x00C7, 0x00E7,
                 0x00D6, 0x00F6, 0x00DC, 0x00FC:
                counts.turkishMarks += 1
                counts.latin += 1
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
                counts.latin += 1
            case 0xAC00...0xD7A3:
                counts.hangul += 1
            case 0x3040...0x30FF:
                counts.kana += 1
            case 0x4E00...0x9FFF:
                counts.han += 1
            case 0x0400...0x04FF:
                counts.cyrillic += 1
            case 0x0600...0x06FF:
                counts.arabic += 1
            case 0x0370...0x03FF:
                counts.greek += 1
            case 0x0590...0x05FF:
                counts.hebrew += 1
            default:
                break
            }
        }
        return counts
    }

    private static func scriptLanguage(in text: String) -> String? {
        let counts = scriptCounts(in: text)
        if !isMostlyLatin(text) {
            if counts.hangul >= 2 { return "ko" }
            if counts.kana >= 3 { return "ja" }
            if counts.han >= 2 && counts.kana == 0 && counts.hangul == 0 { return "zh" }
        }
        if counts.cyrillic >= 3 { return "ru" }
        if counts.arabic >= 3 { return "ar" }
        if counts.greek >= 3 { return "el" }
        if counts.hebrew >= 3 { return "he" }
        if counts.turkishMarks > 0 { return "tr" }
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
