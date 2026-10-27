import AppKit
import CoreGraphics
import ScreenCaptureKit
import ShotNTranslateCore

struct ScreenCaptureFailure: Error {
    var permissionDenied: Bool
}

@MainActor
enum ScreenRegionCapture {
    static func image(in appKitRect: CGRect) async throws -> CGImage {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? appKitRect.maxY
        let rect = CaptureCoordinateSpace.displayRect(fromAppKitRect: appKitRect, primaryScreenMaxY: primaryMaxY)
        return try await withCheckedThrowingContinuation { continuation in
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
