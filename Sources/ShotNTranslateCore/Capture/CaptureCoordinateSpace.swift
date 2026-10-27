import CoreGraphics

public enum CaptureCoordinateSpace {
    /// Converts an AppKit screen rectangle into Quartz global display space.
    /// `primaryScreenMaxY` is the menu-bar screen's `frame.maxY`.
    /// AppKit's origin is the bottom-left of that screen and Y grows upward.
    /// Display space origin is the top-left of that screen and Y grows downward.
    public static func displayRect(fromAppKitRect rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
