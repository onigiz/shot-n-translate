import Foundation

/// Decides whether text read from a quarter-turned screenshot is new.
public enum SidewaysText {
    /// The sideways transcript when it is real text the upright pass did not already contain.
    public static func addition(_ sideways: String, upright: String) -> String {
        let prepared = TranslationText.prepare(sideways)
        guard isReadable(prepared), !alreadyCovered(prepared, by: upright) else { return "" }
        return prepared
    }

    /// A turned page can invent a short misread. Keep a second direction only when it is nearly as strong.
    public static func preferred(
        _ readings: [(text: String, confidence: Float)],
        upright: String
    ) -> [String] {
        let ranked = readings.compactMap { reading -> (String, Float)? in
            let extra = addition(reading.text, upright: upright)
            let letters = letterCount(extra)
            guard letters > 0 else { return nil }
            return (extra, max(reading.confidence, 0.01) * Float(letters))
        }
        guard let best = ranked.max(by: { $0.1 < $1.1 }) else { return [] }
        let comparable = ranked.filter { $0.1 * 10 >= best.1 * 6 }
        var combined = upright
        var kept: [String] = []
        for (text, _) in comparable.sorted(by: { $0.1 > $1.1 }) {
            let novel = addition(text, upright: combined)
            guard !novel.isEmpty else { continue }
            kept.append(novel)
            combined += "\n" + novel
        }
        return kept
    }

    /// Favors a real word over a sideways line that Vision split into short pieces.
    public static func wordScore(_ text: String, confidence: Float) -> Float {
        let prepared = TranslationText.prepare(text)
        guard isReadable(prepared) else { return 0 }
        let longWords = words(prepared).filter { $0.count >= 4 }
        let weighted = longWords.reduce(0) { total, word in
            let capped = min(word.count, 8)
            return total + capped * capped
        }
        guard weighted >= 16 else { return 0 }
        let weight = 0.7 + 0.3 * min(max(confidence, 0), 1)
        return weight * Float(weighted)
    }

    public static func isReadable(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        let letters = scalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 4 else { return false }
        let nonspace = scalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
        guard nonspace > 0 else { return false }
        let meaningful = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        return meaningful * 2 >= nonspace
    }

    private static func alreadyCovered(_ extra: String, by base: String) -> Bool {
        let extraWords = words(extra)
        guard !extraWords.isEmpty else { return false }
        let baseWords = words(base)
        guard !baseWords.isEmpty else { return false }
        let shared = extraWords.intersection(baseWords).count
        return shared * 100 >= extraWords.count * 60
    }

    private static func words(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 }
        )
    }

    private static func letterCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.letters.contains(scalar) {
                count += 1
            }
        }
    }
}
