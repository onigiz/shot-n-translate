import CoreGraphics
import Foundation

public enum PreviewCanvasTool: Equatable, Sendable {
    case rotate
    case crop
    case square
    case circle
}

public enum PreviewMarkKind: Equatable, Sendable {
    case square
    case circle
}

/// A square or circle drawn on the captured image. Bounds use a top-left origin
/// and are normalized to the whole capture, not to the current crop.
public struct PreviewMark: Equatable, Sendable {
    public var kind: PreviewMarkKind
    public var bounds: CGRect
    public var red: Double
    public var green: Double
    public var blue: Double
    /// Stroke width in pixels of the original capture.
    public var strokePixels: Double

    public init(
        kind: PreviewMarkKind,
        bounds: CGRect,
        red: Double,
        green: Double,
        blue: Double,
        strokePixels: Double
    ) {
        self.kind = kind
        self.bounds = bounds
        self.red = red
        self.green = green
        self.blue = blue
        self.strokePixels = strokePixels
    }
}

/// Crop and outlines for the preview image. Recognition still uses the whole capture.
public struct PreviewMarkup: Equatable, Sendable {
    public static let wholeImage = CGRect(x: 0, y: 0, width: 1, height: 1)

    public var crop: CGRect
    public var marks: [PreviewMark]

    public init(crop: CGRect = PreviewMarkup.wholeImage, marks: [PreviewMark] = []) {
        self.crop = crop
        self.marks = marks
    }

    public var isCropped: Bool {
        abs(crop.minX) > 0.001 || abs(crop.minY) > 0.001
            || abs(crop.width - 1) > 0.001 || abs(crop.height - 1) > 0.001
    }

    /// Outline width for a thickness setting. `shorterSide` is the current
    /// picture's shorter side, in the same units the stroke should use.
    public static func strokeWidth(thickness: Double, shorterSide: Double) -> Double {
        let clamped = min(max(thickness, 1), 12)
        return clamped / 12 * 0.06 * max(shorterSide, 1)
    }
}

public enum PreviewMarkupGeometry {
    /// Axis-aligned rectangle from a drag, in normalized top-left coordinates.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Square bounds for a square or a circle. The side follows the longer drag.
    public static func shapeBounds(from start: CGPoint, to end: CGPoint) -> CGRect {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        let width = dx < 0 ? -side : side
        let height = dy < 0 ? -side : side
        return rect(
            from: start,
            to: CGPoint(x: start.x + width, y: start.y + height)
        )
    }

    /// Maps a rectangle drawn on the current crop back onto the whole capture.
    public static func originalBounds(_ visible: CGRect, crop: CGRect) -> CGRect {
        CGRect(
            x: crop.minX + visible.minX * crop.width,
            y: crop.minY + visible.minY * crop.height,
            width: visible.width * crop.width,
            height: visible.height * crop.height
        )
    }

    /// Replaces the crop with the dragged area of what is currently visible.
    public static func crop(_ crop: CGRect, toVisible visible: CGRect) -> CGRect {
        originalBounds(visible, crop: crop)
    }

    /// Converts a canvas point into the visible image, top-left normalized.
    /// `clockwiseDegrees` is the preview rotation. Y grows downward.
    public static func visiblePoint(
        _ point: CGPoint,
        center: CGPoint,
        imageSize: CGSize,
        clockwiseDegrees: Double
    ) -> CGPoint {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let radians = clockwiseDegrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let x = dx * cosine + dy * sine
        let y = -dx * sine + dy * cosine
        let localX = x + Double(imageSize.width) / 2
        let localY = y + Double(imageSize.height) / 2
        return CGPoint(
            x: localX / Double(max(imageSize.width, 1)),
            y: localY / Double(max(imageSize.height, 1))
        )
    }
}

public enum PreviewMarkupImage {
    /// Crops the capture and strokes its outlines. Rotation stays separate.
    public static func image(from source: CGImage, markup: PreviewMarkup) -> CGImage {
        let cropped = croppedImage(source, crop: markup.crop) ?? source
        guard !markup.marks.isEmpty,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: cropped.width,
                height: cropped.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return cropped
        }
        let canvas = CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height)
        context.draw(cropped, in: canvas)
        context.setLineJoin(.miter)
        context.setLineCap(.butt)
        for mark in markup.marks {
            let bounds = pixelBounds(mark.bounds, crop: markup.crop, image: cropped)
            guard bounds.width > 1, bounds.height > 1 else { continue }
            let width = max(CGFloat(mark.strokePixels), 1)
            let inset = bounds.insetBy(dx: width / 2, dy: width / 2)
            guard inset.width > 0, inset.height > 0 else { continue }
            context.setLineWidth(width)
            context.setStrokeColor(CGColor(
                srgbRed: CGFloat(mark.red),
                green: CGFloat(mark.green),
                blue: CGFloat(mark.blue),
                alpha: 1
            ))
            let drawn = CGRect(
                x: inset.minX,
                y: CGFloat(cropped.height) - inset.maxY,
                width: inset.width,
                height: inset.height
            )
            if mark.kind == .circle {
                context.strokeEllipse(in: drawn)
            } else {
                context.stroke(drawn)
            }
        }
        return context.makeImage() ?? cropped
    }

    private static func croppedImage(_ source: CGImage, crop: CGRect) -> CGImage? {
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        guard width > 1, height > 1 else { return source }
        var rect = CGRect(
            x: crop.minX * width,
            y: crop.minY * height,
            width: max(crop.width, 0) * width,
            height: max(crop.height, 0) * height
        ).integral
        rect.origin.x = min(max(rect.minX, 0), width - 1)
        rect.origin.y = min(max(rect.minY, 0), height - 1)
        rect.size.width = min(max(rect.width, 1), width - rect.minX)
        rect.size.height = min(max(rect.height, 1), height - rect.minY)
        if rect.width >= width - 1, rect.height >= height - 1, rect.minX < 1, rect.minY < 1 {
            return source
        }
        return source.cropping(to: rect)
    }

    /// `image` is already the cropped picture. `bounds` is on the whole capture.
    private static func pixelBounds(_ bounds: CGRect, crop: CGRect, image: CGImage) -> CGRect {
        let cropWidth = max(crop.width, 0.000_1)
        let cropHeight = max(crop.height, 0.000_1)
        let x = (bounds.minX - crop.minX) / cropWidth * CGFloat(image.width)
        let y = (bounds.minY - crop.minY) / cropHeight * CGFloat(image.height)
        let width = bounds.width / cropWidth * CGFloat(image.width)
        let height = bounds.height / cropHeight * CGFloat(image.height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
