import CoreGraphics
import Foundation

/// On-disk card metadata. The capture PNG and translation RTF live beside this file.
public struct CardDocument: Equatable, Sendable, Codable {
    public static let currentFormatVersion = 1
    public static let infoFileName = "card.json"
    public static let captureFileName = "capture.png"
    public static let translationFileName = "translation.rtf"

    public var formatVersion: Int
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var editorIsDark: Bool
    public var clockwiseDegrees: Double
    public var markup: CodablePreviewMarkup
    public var previewText: String

    public init(
        formatVersion: Int = CardDocument.currentFormatVersion,
        title: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        editorIsDark: Bool,
        clockwiseDegrees: Double,
        markup: PreviewMarkup,
        previewText: String
    ) {
        self.formatVersion = formatVersion
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.editorIsDark = editorIsDark
        self.clockwiseDegrees = clockwiseDegrees
        self.markup = CodablePreviewMarkup(markup)
        self.previewText = previewText
    }

    public var previewMarkup: PreviewMarkup {
        markup.markup
    }
}

public struct LibraryCardSummary: Equatable, Sendable, Identifiable {
    public var id: URL { packageURL }
    public var packageURL: URL
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var previewText: String
    public var editorIsDark: Bool

    public init(
        packageURL: URL,
        title: String,
        createdAt: Date,
        modifiedAt: Date,
        previewText: String,
        editorIsDark: Bool
    ) {
        self.packageURL = packageURL
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.previewText = previewText
        self.editorIsDark = editorIsDark
    }
}

public struct CodablePreviewMarkup: Equatable, Sendable, Codable {
    public var crop: CodableRect
    public var marks: [CodablePreviewMark]

    public init(_ markup: PreviewMarkup) {
        crop = CodableRect(markup.crop)
        marks = markup.marks.map(CodablePreviewMark.init)
    }

    public var markup: PreviewMarkup {
        PreviewMarkup(crop: crop.rect, marks: marks.map(\.mark))
    }
}

public struct CodablePreviewMark: Equatable, Sendable, Codable {
    public var kind: String
    public var bounds: CodableRect
    public var red: Double
    public var green: Double
    public var blue: Double
    public var strokePixels: Double

    public init(_ mark: PreviewMark) {
        kind = mark.kind == .circle ? "circle" : "square"
        bounds = CodableRect(mark.bounds)
        red = mark.red
        green = mark.green
        blue = mark.blue
        strokePixels = mark.strokePixels
    }

    public var mark: PreviewMark {
        PreviewMark(
            kind: kind == "circle" ? .circle : .square,
            bounds: bounds.rect,
            red: red,
            green: green,
            blue: blue,
            strokePixels: strokePixels
        )
    }
}

public struct CodableRect: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
