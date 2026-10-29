import CoreGraphics

/// Turns a screenshot by 90 degrees so sideways text can be read as horizontal lines.
/// The preview keeps the original image. Only recognition uses the turned copy.
public enum ImageQuarterTurn: Sendable {
    case clockwise
    case counterClockwise

    public var opposite: ImageQuarterTurn {
        switch self {
        case .clockwise: .counterClockwise
        case .counterClockwise: .clockwise
        }
    }

    /// A new image whose pixels are this quarter turn of `image`.
    public func image(from image: CGImage) -> CGImage? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let bitmapInfos: [UInt32] = [
            CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue,
            CGImageAlphaInfo.noneSkipLast.rawValue
        ]
        var best: CGImage?
        var bestPeak = -1
        for bitmapInfo in bitmapInfos {
            guard let context = CGContext(
                data: nil,
                width: sourceHeight,
                height: sourceWidth,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                continue
            }
            switch self {
            case .clockwise:
                context.translateBy(x: CGFloat(sourceHeight), y: 0)
                context.rotate(by: .pi / 2)
            case .counterClockwise:
                context.translateBy(x: 0, y: CGFloat(sourceWidth))
                context.rotate(by: -.pi / 2)
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
            guard let rendered = context.makeImage() else { continue }
            let peak = peakLuminance(rendered)
            if peak > bestPeak {
                best = rendered
                bestPeak = peak
            }
        }
        return best
    }

    /// Maps a Vision box from the turned image back into the original image.
    /// Both rectangles use a bottom-left origin and are normalized.
    public func boundsInOriginal(
        _ bounds: CGRect,
        originalWidth: CGFloat,
        originalHeight: CGFloat
    ) -> CGRect {
        guard originalWidth > 0, originalHeight > 0 else { return .zero }
        let mapped = normalizedRect(bounds) { point in
            switch self {
            case .clockwise:
                CGPoint(x: point.y, y: 1 - point.x)
            case .counterClockwise:
                CGPoint(x: 1 - point.y, y: point.x)
            }
        }
        return mapped
    }

    /// Maps a normalized box in the original image into the turned image.
    public func boundsAfterTurn(
        _ bounds: CGRect,
        originalWidth: CGFloat,
        originalHeight: CGFloat
    ) -> CGRect {
        guard originalWidth > 0, originalHeight > 0 else { return .zero }
        return normalizedRect(bounds) { point in
            switch self {
            case .clockwise:
                CGPoint(x: 1 - point.y, y: point.x)
            case .counterClockwise:
                CGPoint(x: point.y, y: 1 - point.x)
            }
        }
    }

    private func normalizedRect(_ bounds: CGRect, _ transform: (CGPoint) -> CGPoint) -> CGRect {
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        ].map(transform)
        let minX = corners.map(\.x).min() ?? 0
        let maxX = corners.map(\.x).max() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        let maxY = corners.map(\.y).max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func peakLuminance(_ image: CGImage) -> Int {
        guard image.bitsPerComponent == 8,
              let data = image.dataProvider?.data,
              let base = CFDataGetBytePtr(data) else {
            return 0
        }
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 3 else { return 0 }
        var peak = 0
        let stepX = max(image.width / 16, 1)
        let stepY = max(image.height / 16, 1)
        for y in stride(from: 0, to: image.height, by: stepY) {
            for x in stride(from: 0, to: image.width, by: stepX) {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                guard offset + 2 < CFDataGetLength(data) else { continue }
                peak = max(peak, Int(base[offset]), Int(base[offset + 1]), Int(base[offset + 2]))
            }
        }
        return peak
    }
}
