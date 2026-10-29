import AppKit
import CoreGraphics
import CoreText
import Foundation

public enum TranslationPreviewPDFError: Error, Equatable, CustomStringConvertible {
    case emptyTranslation
    case cannotCreateDocument
    case cannotWrite

    public var description: String {
        switch self {
        case .emptyTranslation: "The translation is empty."
        case .cannotCreateDocument: "The PDF could not be created."
        case .cannotWrite: "The PDF could not be written."
        }
    }
}

/// First PDF for a capture: the screenshot on top, the translation underneath.
public enum TranslationPreviewPDF {
    public static func write(image: CGImage, translation: String, to url: URL) throws {
        let document = NSAttributedString(string: translation, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.black
        ])
        try write(image: image, document: document, darkBackground: false, to: url)
    }

    public static func write(
        image: CGImage,
        document: NSAttributedString,
        darkBackground: Bool,
        to url: URL
    ) throws {
        let data = try pdfData(image: image, document: document, darkBackground: darkBackground)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw TranslationPreviewPDFError.cannotWrite
        }
    }

    public static func pdfData(
        image: CGImage,
        document: NSAttributedString,
        darkBackground: Bool
    ) throws -> Data {
        let text = document.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationPreviewPDFError.emptyTranslation }
        let prepared = coreTextDocument(document)
        let framesetter = CTFramesetterCreateWithAttributedString(prepared)
        let length = CFAttributedStringGetLength(prepared)

        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 36
        let contentWidth = pageWidth - margin * 2

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw TranslationPreviewPDFError.cannotCreateDocument
        }
        var media = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw TranslationPreviewPDFError.cannotCreateDocument
        }

        var location = 0
        var pageIndex = 0
        while location < length && pageIndex < 40 {
            context.beginPDFPage(nil)
            context.interpolationQuality = .high
            context.setFillColor(darkBackground ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            var textTop = pageHeight - margin
            if pageIndex == 0 {
                let placed = imagePlacement(image, contentWidth: contentWidth, maxHeight: 460)
                let originX = margin + (contentWidth - placed.width) / 2
                let imageRect = CGRect(
                    x: originX,
                    y: pageHeight - margin - placed.height,
                    width: placed.width,
                    height: placed.height
                )
                context.draw(image, in: imageRect)
                textTop = imageRect.minY - 18
            }
            let textHeight = max(textTop - margin, 1)
            let textRect = CGRect(x: margin, y: margin, width: contentWidth, height: textHeight)
            if textRect.height >= 24 {
                let path = CGPath(rect: textRect, transform: nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: location, length: 0),
                    path,
                    nil
                )
                CTFrameDraw(frame, context)
                let visible = CTFrameGetVisibleStringRange(frame)
                let next = visible.location + visible.length
                if next <= location {
                    context.endPDFPage()
                    break
                }
                location = next
            }
            context.endPDFPage()
            pageIndex += 1
            if textRect.height < 24 {
                continue
            }
        }
        context.closePDF()
        guard data.length > 0 else { throw TranslationPreviewPDFError.cannotCreateDocument }
        return data as Data
    }

    private static func imagePlacement(
        _ image: CGImage,
        contentWidth: CGFloat,
        maxHeight: CGFloat
    ) -> CGSize {
        let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
        var width = contentWidth
        var height = width * aspect
        if height > maxHeight, aspect > 0 {
            height = maxHeight
            width = height / aspect
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    /// Core Text reads fonts and colors from its own attribute keys.
    private static func coreTextDocument(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)
        result.enumerateAttributes(in: full, options: []) { attributes, range, _ in
            if let font = attributes[.font] as? NSFont {
                let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
                result.addAttribute(.init(kCTFontAttributeName as String), value: ctFont, range: range)
            }
            if let color = attributes[.foregroundColor] as? NSColor {
                result.addAttribute(
                    .init(kCTForegroundColorAttributeName as String),
                    value: color.cgColor,
                    range: range
                )
            }
            if let style = attributes[.underlineStyle] as? Int, style != 0 {
                result.addAttribute(.init(kCTUnderlineStyleAttributeName as String), value: style, range: range)
            }
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
               let ctParagraph = paragraphStyle(paragraph) {
                result.addAttribute(
                    .init(kCTParagraphStyleAttributeName as String),
                    value: ctParagraph,
                    range: range
                )
            }
        }
        return result
    }

    private static func paragraphStyle(_ paragraph: NSParagraphStyle) -> CTParagraphStyle? {
        var alignment = CTTextAlignment.left
        switch paragraph.alignment {
        case .center: alignment = .center
        case .right: alignment = .right
        default: alignment = .left
        }
        var lineSpacing = paragraph.lineSpacing
        return withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineSpacing) { spacingPointer in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentPointer
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineSpacingAdjustment,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: spacingPointer
                    )
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }
}
