import AppKit
import CoreGraphics
import ScreenCaptureKit
import ShotNTranslateCore

struct ScreenCaptureFailure: Error {
    var permissionDenied: Bool
}

@MainActor
enum ScreenRegionCapture {
    /// Quartz display space. This is the rectangle ScreenCaptureKit expects.
    static func displayImage(forAppKitRect rect: CGRect) async throws -> CGImage {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        let displayRect = CaptureCoordinateSpace.displayRect(fromAppKitRect: rect, primaryScreenMaxY: primaryMaxY)
        return try await capture(displayRect)
    }

    /// The same rectangle without the Y flip. Used only when the display-space
    /// capture is blank, so a wrong coordinate space is not preferred over a real page.
    static func rawImage(forAppKitRect rect: CGRect) async throws -> CGImage {
        try await capture(rect)
    }

    private static func capture(_ rect: CGRect) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: rect) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? ScreenCaptureFailure(permissionDenied: false))
                }
            }
        }
    }

    static func permissionDenied(_ error: Error) -> Bool {
        if let failure = error as? ScreenCaptureFailure {
            return failure.permissionDenied
        }
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return false }
        return nsError.code == SCStreamError.userDeclined.rawValue
            || nsError.code == SCStreamError.missingEntitlements.rawValue
    }
}
