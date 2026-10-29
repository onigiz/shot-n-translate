import Foundation

/// One full circle of screenshot rotations, every 5 degrees.
/// 0 degrees is the upright recognition pass.
/// 90, 180, and 270 degrees use exact quarter and half turns.
public enum ImageRotationSweep {
    public static let stepDegrees = 5

    /// 0, 5, 10, ... 355.
    public static var degrees: [Int] {
        Array(stride(from: 0, to: 360, by: stepDegrees))
    }

    /// Rotations handled by a free turn rather than the upright, quarter, or half-turn passes.
    public static var probeDegrees: [Int] {
        degrees.filter { $0 != 0 && $0 != 90 && $0 != 180 && $0 != 270 }
    }
}
