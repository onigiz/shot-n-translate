import CoreGraphics
import Foundation

/// Rotates a screenshot by any angle so upside-down or diagonal text can be read upright.
/// The preview keeps the original image. Only recognition uses the rotated copy.
public struct ImageFreeRotation: Sendable, Equatable {
    /// Counter-clockwise radians in a bottom-left coordinate space.
    public var radians: CGFloat

    public init(radians: CGFloat) {
        self.radians = radians
    }

    public func image(from image: CGImage) -> CGImage? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let canvas = canvasPixels(width: sourceWidth, height: sourceHeight)
        let bitmapInfos: [UInt32] = [
            CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue,
            CGImageAlphaInfo.noneSkipLast.rawValue
        ]
        let rightAngle = abs(sin(radians * 2)) < 0.02
        var best: CGImage?
        var bestPeak = -1
        for bitmapInfo in bitmapInfos {
            guard let context = CGContext(
                data: nil,
                width: canvas.width,
                height: canvas.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                continue
            }
            context.interpolationQuality = rightAngle ? .none : .medium
            context.translateBy(x: CGFloat(canvas.width) / 2, y: CGFloat(canvas.height) / 2)
            context.rotate(by: radians)
            context.translateBy(x: -CGFloat(sourceWidth) / 2, y: -CGFloat(sourceHeight) / 2)
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

    /// Maps a Vision box from the rotated image back into the original image.
    /// Both rectangles use a bottom-left origin and are normalized.
    public func boundsInOriginal(
        _ bounds: CGRect,
        originalWidth: CGFloat,
        originalHeight: CGFloat
    ) -> CGRect {
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        ].map {
            normalizedPointInOriginal($0, originalWidth: originalWidth, originalHeight: originalHeight)
        }
        let minX = corners.map(\.x).min() ?? 0
        let maxX = corners.map(\.x).max() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        let maxY = corners.map(\.y).max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func normalizedPointInOriginal(
        _ point: CGPoint,
        originalWidth: CGFloat,
        originalHeight: CGFloat
    ) -> CGPoint {
        let canvas = canvasPixels(width: Int(originalWidth.rounded()), height: Int(originalHeight.rounded()))
        let dx = point.x * CGFloat(canvas.width) - CGFloat(canvas.width) / 2
        let dy = point.y * CGFloat(canvas.height) - CGFloat(canvas.height) / 2
        let cosine = components().cosine
        let sine = components().sine
        let x = dx * cosine + dy * sine + originalWidth / 2
        let y = -dx * sine + dy * cosine + originalHeight / 2
        return CGPoint(x: x / originalWidth, y: y / originalHeight)
    }

    public func normalizedPointAfterTurn(
        _ point: CGPoint,
        originalWidth: CGFloat,
        originalHeight: CGFloat
    ) -> CGPoint {
        let canvas = canvasPixels(width: Int(originalWidth.rounded()), height: Int(originalHeight.rounded()))
        let centeredX = point.x * originalWidth - originalWidth / 2
        let centeredY = point.y * originalHeight - originalHeight / 2
        let cosine = components().cosine
        let sine = components().sine
        let x = centeredX * cosine - centeredY * sine + CGFloat(canvas.width) / 2
        let y = centeredX * sine + centeredY * cosine + CGFloat(canvas.height) / 2
        return CGPoint(x: x / CGFloat(canvas.width), y: y / CGFloat(canvas.height))
    }

    private func canvasPixels(width: Int, height: Int) -> (width: Int, height: Int) {
        let axis = components()
        let absoluteCosine = abs(axis.cosine)
        let absoluteSine = abs(axis.sine)
        let width = CGFloat(width)
        let height = CGFloat(height)
        return (
            max(Int((width * absoluteCosine + height * absoluteSine).rounded(.up)), 1),
            max(Int((width * absoluteSine + height * absoluteCosine).rounded(.up)), 1)
        )
    }

    private func components() -> (cosine: CGFloat, sine: CGFloat) {
        let cosine = cos(radians)
        let sine = sin(radians)
        if abs(sine) < 0.0001 {
            return (cosine < 0 ? -1 : 1, 0)
        }
        if abs(cosine) < 0.0001 {
            return (0, sine < 0 ? -1 : 1)
        }
        return (cosine, sine)
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
