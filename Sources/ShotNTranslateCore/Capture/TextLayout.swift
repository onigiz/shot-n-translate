import CoreGraphics
import Foundation

/// One OCR line. `bounds` uses a bottom-left origin, normalized to the full image.
public struct TextLineBox: Equatable, Sendable {
    public var text: String
    public var bounds: CGRect
    /// Vision's confidence for this line, from 0 to 1. Layout-only boxes use 1.
    public var confidence: Float

    public init(text: String, bounds: CGRect, confidence: Float = 1) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// Rebuilds paragraphs and headings from the gaps and sizes of OCR lines.
public enum TextLayout {
    public static func transcript(from lines: [TextLineBox]) -> String {
        let expanded = lines.flatMap { line -> [TextLineBox] in
            TranslationText.splitGluedHeading(line.text).map { part in
                TextLineBox(text: part, bounds: line.bounds)
            }
        }.filter { !TranslationText.isDecorativeRule($0.text) && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let rows = deduplicated(cluster(expanded))
        let ordered = rows.sorted { $0.bounds.midY > $1.bounds.midY }
        guard !ordered.isEmpty else { return "" }

        let bodyHeights = ordered
            .filter { !TranslationText.isHeadingLine($0.text) }
            .map(\.bounds.height)
            .sorted()
        let heights = bodyHeights.isEmpty ? ordered.map(\.bounds.height).sorted() : bodyHeights
        let medianHeight = heights[heights.count / 2]
        var smallGaps: [CGFloat] = []
        for index in 0..<(ordered.count - 1) {
            let gap = ordered[index].bounds.minY - ordered[index + 1].bounds.maxY
            if gap > 0, gap < max(medianHeight, 0.001) {
                smallGaps.append(gap)
            }
        }
        smallGaps.sort()
        let normalGap = smallGaps.isEmpty ? medianHeight * 0.35 : smallGaps[smallGaps.count / 2]
        let paragraphGap = max(normalGap * 1.75, medianHeight * 0.8)

        var blocks: [String] = []
        var current: [String] = []

        func flush() {
            let text = current.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(text)
            }
            current = []
        }

        for (index, row) in ordered.enumerated() {
            let heading = TranslationText.isHeadingLine(row.text)
            if heading {
                flush()
                blocks.append(row.text.trimmingCharacters(in: CharacterSet(charactersIn: "| \t")))
                continue
            }
            if index > 0, !current.isEmpty {
                let above = ordered[index - 1]
                let gap = above.bounds.minY - row.bounds.maxY
                if gap >= paragraphGap {
                    flush()
                }
            }
            current.append(row.text)
        }
        flush()
        return blocks.joined(separator: "\n\n")
    }

    /// Maps a Vision box from a cropped band into the full image.
    /// `band` is the crop in top-left pixel coordinates.
    public static func globalBounds(
        _ bounds: CGRect,
        band: CGRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGRect {
        let width = max(imageWidth, 1)
        let height = max(imageHeight, 1)
        return CGRect(
            x: (band.minX + bounds.minX * band.width) / width,
            y: (height - band.maxY + bounds.minY * band.height) / height,
            width: bounds.width * band.width / width,
            height: bounds.height * band.height / height
        )
    }

    private static func cluster(_ lines: [TextLineBox]) -> [TextLineBox] {
        let sorted = lines.sorted { lhs, rhs in
            if abs(lhs.bounds.midY - rhs.bounds.midY) > max(lhs.bounds.height, rhs.bounds.height) * 0.45 {
                return lhs.bounds.midY > rhs.bounds.midY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        var rows: [[TextLineBox]] = []
        for line in sorted {
            if let index = rows.indices.last, let anchor = rows[index].first, sameRow(anchor.bounds, line.bounds) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            let ordered = row.sorted { $0.bounds.minX < $1.bounds.minX }
            let text = ordered.map(\.text).joined(separator: " ")
            let union = ordered.dropFirst().reduce(ordered[0].bounds) { $0.union($1.bounds) }
            return TextLineBox(text: text, bounds: union)
        }
    }

    private static func sameRow(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY)
        let minHeight = min(lhs.height, rhs.height)
        return minHeight > 0 && overlap > minHeight * 0.4
    }

    private static func deduplicated(_ lines: [TextLineBox]) -> [TextLineBox] {
        var kept: [TextLineBox] = []
        for line in lines {
            let duplicate = kept.contains { existing in
                existing.text == line.text
                    && abs(existing.bounds.midY - line.bounds.midY) < max(existing.bounds.height, line.bounds.height)
            }
            if !duplicate {
                kept.append(line)
            }
        }
        return kept
    }
}
