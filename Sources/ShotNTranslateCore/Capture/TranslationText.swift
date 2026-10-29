import Foundation
import NaturalLanguage

/// Turns OCR lines into paragraphs before Apple Translation sees them.
/// A visual line break is not a sentence break. Blank lines and list items stay apart.
public enum TranslationText {
    /// Joins wrapped lines, removes end-of-line hyphenation, and keeps paragraph breaks.
    public static func prepare(_ raw: String) -> String {
        let lines = expandedLines(raw)
        let fullWidth = lines.map(\.count).max() ?? 0
        var paragraphs: [String] = []
        var current: [String] = []

        func flush() {
            let paragraph = join(current)
            if !paragraph.isEmpty {
                paragraphs.append(paragraph)
            }
            current = []
        }

        for trimmed in lines {
            if trimmed.isEmpty {
                flush()
                continue
            }
            if isDecorativeRule(trimmed) {
                flush()
                continue
            }
            if isHeadingLine(trimmed) {
                flush()
                paragraphs.append(trimmed)
                continue
            }
            if isBullet(trimmed) {
                if !current.isEmpty {
                    flush()
                }
                current = [trimmed]
                continue
            }
            if let last = current.last,
               isParagraphEndingLine(last, fullWidth: fullWidth),
               startsParagraph(trimmed) {
                flush()
            }
            current.append(trimmed)
        }
        flush()
        return paragraphs.joined(separator: "\n\n")
    }

    /// Paragraphs produced by `prepare`, in reading order.
    public static func paragraphs(in prepared: String) -> [String] {
        prepared
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// When two transcripts contain about the same letters, the one that kept
    /// paragraph breaks wins. A flat copy of one paragraph still loses to fewer visual lines.
    public static func isPreferred(_ candidate: String, over other: String) -> Bool {
        let left = metrics(candidate)
        let right = metrics(other)
        if left.paragraphs != right.paragraphs {
            let structuredLetters = left.paragraphs > right.paragraphs ? left.letters : right.letters
            let otherLetters = left.paragraphs > right.paragraphs ? right.letters : left.letters
            if structuredLetters * 100 >= otherLetters * 70 {
                return left.paragraphs > right.paragraphs
            }
        }
        let baseline = max(left.letters, right.letters, 1)
        if abs(left.letters - right.letters) * 100 / baseline > 12 {
            return left.letters > right.letters
        }
        if left.paragraphs != right.paragraphs {
            return left.paragraphs > right.paragraphs
        }
        if left.rawLines != right.rawLines {
            return left.rawLines < right.rawLines
        }
        return left.letters > right.letters
    }

    private static func metrics(_ text: String) -> (letters: Int, rawLines: Int, paragraphs: Int) {
        let prepared = prepare(text)
        let letters = prepared.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.letters.contains(scalar) {
                count += 1
            }
        }
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: true).count
        return (letters, rawLines, paragraphs(in: prepared).count)
    }

    static func expandedLines(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .flatMap { splitGluedHeading($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// "Languages|AppLanguage..." is a heading whose underline was read as a bar.
    static func splitGluedHeading(_ line: String) -> [String] {
        guard let bar = line.firstIndex(of: "|") else { return [line] }
        let left = String(line[..<bar]).trimmingCharacters(in: .whitespaces)
        let right = String(line[line.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
        guard isHeadingLine(left), right.contains(where: \.isLetter) else { return [line] }
        return [left, right]
    }

    static func isDecorativeRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let marks = CharacterSet(charactersIn: "-–—_|.=·• ")
        return trimmed.unicodeScalars.allSatisfy { marks.contains($0) }
    }

    /// A short title such as "Languages" or "Translation", not a wrapped sentence.
    static func isHeadingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "| \t"))
        guard !trimmed.isEmpty, trimmed.count <= 18 else { return false }
        guard !endsSentence(trimmed), !isBullet(trimmed), !isDecorativeRule(trimmed) else { return false }
        let words = trimmed.split(separator: " ")
        guard (1...3).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }
    }

    private static func join(_ lines: [String]) -> String {
        guard var result = lines.first else { return "" }
        for line in lines.dropFirst() {
            if let joined = joiningHyphen(result, line) {
                result = joined
            } else {
                result += " " + line
            }
        }
        return normalizeSentences(result)
    }

    /// "com-" + "puter" becomes "computer". A digit range such as "2020-" + "2024" keeps the hyphen.
    private static func joiningHyphen(_ left: String, _ right: String) -> String? {
        guard left.hasSuffix("-") || left.hasSuffix("\u{00AD}") else { return nil }
        let stem = String(left.dropLast())
        guard let last = stem.unicodeScalars.last, let first = right.unicodeScalars.first else { return nil }
        if CharacterSet.letters.contains(last), CharacterSet.letters.contains(first) {
            return stem + right
        }
        if CharacterSet.decimalDigits.contains(last), CharacterSet.decimalDigits.contains(first) {
            return stem + "-" + right
        }
        return nil
    }

    /// A short line that finishes a sentence, followed by a new capitalised line, is a paragraph.
    /// A full-width line that happens to end with a period stays in the same paragraph.
    private static func isParagraphEndingLine(_ line: String, fullWidth: Int) -> Bool {
        guard fullWidth >= 24, endsSentence(line) else { return false }
        return line.count * 100 / fullWidth < 72
    }

    private static func endsSentence(_ line: String) -> Bool {
        var end = line
        while let last = end.last, "\"'”’)]".contains(last) {
            end.removeLast()
        }
        guard let punct = end.last, ".!?…。！？".contains(punct) else { return false }
        let word = end.dropLast().split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        if punct == ".", word.count <= 2 { return false }
        return true
    }

    private static func startsParagraph(_ line: String) -> Bool {
        guard let first = line.first(where: { !"\"'“‘([«".contains($0) }) else { return false }
        return first.isUppercase || first.isNumber
    }

    private static func isBullet(_ line: String) -> Bool {
        let markers = ["- ", "– ", "— ", "* ", "• ", "● ", "▪ "]
        if markers.contains(where: { line.hasPrefix($0) }) {
            return line.count > 2
        }
        guard let first = line.first, first.isNumber else { return false }
        let rest = line.drop(while: \.isNumber)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    private static func normalizeSentences(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        guard !sentences.isEmpty else { return text }
        return sentences.joined(separator: " ")
    }
}
