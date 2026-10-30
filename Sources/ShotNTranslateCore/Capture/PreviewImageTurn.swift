import CoreGraphics
import Foundation

/// User rotation of the preview image. Recognition keeps the captured pixels.
/// Degrees are clockwise. Zero leaves the captured image unchanged.
public struct PreviewImageTurn: Equatable, Sendable {
    public var clockwiseDegrees: Double

    public init(clockwiseDegrees: Double) {
        self.clockwiseDegrees = Self.normalized(clockwiseDegrees)
    }

    /// Folds any clockwise angle into the short turn, from just past -180 up through 180.
    public static func normalized(_ degrees: Double) -> Double {
        let turns = degrees.truncatingRemainder(dividingBy: 360)
        var value = turns
        if value <= -180 { value += 360 }
        if value > 180 { value -= 360 }
        if abs(value) < 0.000_001 { return 0 }
        return value
    }

    public func turned(by degrees: Double) -> PreviewImageTurn {
        PreviewImageTurn(clockwiseDegrees: clockwiseDegrees + degrees)
    }

    /// The image written into the PDF. The preview draws this same turn around its center.
    public func image(from image: CGImage) -> CGImage {
        guard clockwiseDegrees != 0 else { return image }
        let radians = -CGFloat(clockwiseDegrees) * .pi / 180
        return ImageFreeRotation(radians: radians).image(from: image) ?? image
    }
}

/// Drag math for the preview's rotation handle. The handle sits above the image
/// and the image turns around its own center.
public enum PreviewRotationDrag {
    /// Clockwise degrees from straight up, in a coordinate space where x grows
    /// right and y grows down. Returns nil when the point is on the center.
    public static func clockwiseDegrees(from center: CGPoint, to point: CGPoint) -> Double? {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        guard dx * dx + dy * dy > 1 else { return nil }
        return atan2(dx, -dy) * 180 / .pi
    }

    public static func imageDegrees(
        startDegrees: Double,
        grabDegrees: Double,
        pointerDegrees: Double
    ) -> Double {
        PreviewImageTurn.normalized(startDegrees + pointerDegrees - grabDegrees)
    }

    /// Offset from the image center to the handle. Zero degrees is straight up.
    public static func handleOffset(imageHeight: CGFloat, gap: CGFloat, clockwiseDegrees: Double) -> CGPoint {
        let radius = Double(imageHeight / 2 + gap)
        let radians = clockwiseDegrees * .pi / 180
        let dx = 0.0
        let dy = -radius
        return CGPoint(
            x: dx * cos(radians) - dy * sin(radians),
            y: dx * sin(radians) + dy * cos(radians)
        )
    }
}
