import AppKit
import CoreGraphics
import CoreVideo
import ScreenCaptureKit
import ShotNTranslateCore

struct ScreenCaptureFailure: Error {
    var permissionDenied: Bool
}

@MainActor
enum ScreenRegionCapture {
    /// Captures the selection from the display that actually contains it.
    /// `SCScreenshotManager.captureImage(in:)` only reads the main display, so a
    /// region on another screen comes back black.
    static func image(forAppKitRect rect: CGRect) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw map(error)
        }
        guard let screen = screen(containing: rect),
              let display = content.displays.first(where: { $0.displayID == displayID(of: screen) })
                ?? content.displays.first
        else {
            throw ScreenCaptureFailure(permissionDenied: false)
        }

        let filter = contentFilter(for: display, content: content)
        let local = CaptureCoordinateSpace.localDisplayRect(appKitRect: rect, screenFrame: screen.frame)
        guard local.width >= 1, local.height >= 1 else {
            throw ScreenCaptureFailure(permissionDenied: false)
        }

        let primary = try await capture(filter: filter, localRect: local, scale: screen.backingScaleFactor)
        if TextRecognizer.brightPixelFraction(primary) >= 0.01 {
            return primary
        }

        // Some capture paths keep AppKit's bottom-left origin. Use that only when the
        // top-left capture has no light text pixels.
        let appKitLocal = CGRect(
            x: local.origin.x,
            y: screen.frame.height - local.maxY,
            width: local.width,
            height: local.height
        )
        if let alternate = try? await capture(filter: filter, localRect: appKitLocal, scale: screen.backingScaleFactor),
           TextRecognizer.brightPixelFraction(alternate) > TextRecognizer.brightPixelFraction(primary) {
            return alternate
        }
        return primary
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

    private static func capture(filter: SCContentFilter, localRect: CGRect, scale: CGFloat) async throws -> CGImage {
        let measuredScale = CGFloat(filter.pointPixelScale)
        let pointScale = measuredScale > 0 ? measuredScale : max(scale, 1)
        let pixelsWide = max(Int((localRect.width * pointScale).rounded()), 1)
        let pixelsHigh = max(Int((localRect.height * pointScale).rounded()), 1)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = pixelsWide
        configuration.height = pixelsHigh
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.shouldBeOpaque = true
        // An unset format lets an HDR display return a buffer that AppKit and Vision
        // both read as an empty black image.
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw map(error)
        }
    }

    private static func contentFilter(for display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier
        let ownApps = content.applications.filter { app in
            app.processID == pid || (bundleID != nil && app.bundleIdentifier == bundleID)
        }
        if ownApps.isEmpty {
            return SCContentFilter(display: display, excludingWindows: [])
        }
        return SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        let match = screens.max { lhs, rhs in
            area(lhs.frame.intersection(rect)) < area(rhs.frame.intersection(rect))
        }
        if let match, area(match.frame.intersection(rect)) > 0 {
            return match
        }
        return screens.first
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else { return 0 }
        return max(rect.width, 0) * max(rect.height, 0)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.uint32Value
        }
        return CGMainDisplayID()
    }

    private static func map(_ error: Error) -> Error {
        if permissionDenied(error) {
            return ScreenCaptureFailure(permissionDenied: true)
        }
        return error
    }
}
