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

    /// The part of `appKitRect` that lies on `screenFrame`, in that display's local
    /// points. The origin is the top-left of the display and Y grows downward.
    /// ScreenCaptureKit's `sourceRect` uses this space, including on a secondary display.
    public static func localDisplayRect(appKitRect: CGRect, screenFrame: CGRect) -> CGRect {
        let clipped = appKitRect.intersection(screenFrame)
        guard !clipped.isNull, !clipped.isEmpty, clipped.width >= 1, clipped.height >= 1 else {
            return .zero
        }
        return CGRect(
            x: clipped.origin.x - screenFrame.origin.x,
            y: screenFrame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )
    }

    /// `screencapture -R` expects `x,y,w,h` in Quartz global points (top-left origin).
    public static func screencaptureRectArgument(_ rect: CGRect) -> String {
        let x = Int(rect.origin.x.rounded())
        let y = Int(rect.origin.y.rounded())
        let width = max(Int(rect.width.rounded()), 1)
        let height = max(Int(rect.height.rounded()), 1)
        return "\(x),\(y),\(width),\(height)"
    }
}
