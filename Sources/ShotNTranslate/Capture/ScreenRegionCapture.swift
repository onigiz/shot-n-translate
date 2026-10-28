import AppKit
import CoreGraphics
import CoreVideo
import ScreenCaptureKit
import ShotNTranslateCore

struct ScreenCaptureFailure: Error {
    var permissionDenied: Bool
}

/// `SCShareableContent` is not Sendable. The box lets a background callback
/// publish it without a system permission prompt.
private final class ShareableContentBox: @unchecked Sendable {
    var content: SCShareableContent?
    var error: Error?
}

@MainActor
enum ScreenRegionCapture {
    /// Captures the selection from the display that actually contains it.
    /// Asking the system for permission again is intentionally not done here.
    /// The Settings switch can already be on while `CGRequestScreenCaptureAccess`
    /// still presents a dialog, which traps the user in a grant loop.
    static func image(forAppKitRect rect: CGRect) async throws -> CGImage {
        guard let screen = screen(containing: rect) else {
            throw ScreenCaptureFailure(permissionDenied: false)
        }
        let local = CaptureCoordinateSpace.localDisplayRect(appKitRect: rect, screenFrame: screen.frame)
        guard local.width >= 1, local.height >= 1 else {
            throw ScreenCaptureFailure(permissionDenied: false)
        }
        let quartz = CaptureCoordinateSpace.displayRect(
            fromAppKitRect: rect,
            primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        )
        let appKitLocal = CGRect(
            x: local.origin.x,
            y: screen.frame.height - local.maxY,
            width: local.width,
            height: local.height
        )

        var best: CGImage?
        var bestScore = -1.0
        var sawPermissionError = false

        func consider(_ image: CGImage) {
            let score = TextRecognizer.brightPixelFraction(image)
            if score > bestScore {
                best = image
                bestScore = score
            }
        }
        func note(_ error: Error) {
            if permissionDenied(error) {
                sawPermissionError = true
            }
        }

        if let content = try? await loadShareableContent() {
            let display = content.displays.first { $0.displayID == displayID(of: screen) }
                ?? content.displays.first
            if let display {
                let filter = contentFilter(for: display, content: content)
                for candidate in [local, appKitLocal] {
                    do {
                        consider(try await capture(filter: filter, localRect: candidate, scale: screen.backingScaleFactor))
                    } catch {
                        note(error)
                    }
                    if bestScore >= 0.01 {
                        return best!
                    }
                }
            }
        } else {
            sawPermissionError = !CGPreflightScreenCaptureAccess()
        }

        do {
            consider(try await captureRect(quartz))
        } catch {
            note(error)
        }
        if bestScore < 0.01 {
            do {
                consider(try await captureRect(rect))
            } catch {
                note(error)
            }
        }

        if let best {
            return best
        }
        // The switch in System Settings can be on for this app while a fresh
        // permission dialog still appears. Never request access from here.
        if sawPermissionError && !CGPreflightScreenCaptureAccess() {
            throw ScreenCaptureFailure(permissionDenied: true)
        }
        throw ScreenCaptureFailure(permissionDenied: false)
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

    /// Listing shareable content on the main thread reports a false denial even
    /// after Screen Recording has been allowed. The callback runs off the main thread.
    private static func loadShareableContent() async throws -> SCShareableContent {
        let box = ShareableContentBox()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                    box.content = content
                    box.error = error
                    continuation.resume()
                }
            }
        }
        if let content = box.content {
            return content
        }
        throw box.error ?? ScreenCaptureFailure(permissionDenied: false)
    }

    private static func capture(filter: SCContentFilter, localRect: CGRect, scale: CGFloat) async throws -> CGImage {
        let measuredScale = CGFloat(filter.pointPixelScale)
        let pointScale = measuredScale > 0 ? measuredScale : max(scale, 1)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = max(Int((localRect.width * pointScale).rounded()), 1)
        configuration.height = max(Int((localRect.height * pointScale).rounded()), 1)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.shouldBeOpaque = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private static func captureRect(_ rect: CGRect) async throws -> CGImage {
        try await SCScreenshotManager.captureImage(in: rect)
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
}
