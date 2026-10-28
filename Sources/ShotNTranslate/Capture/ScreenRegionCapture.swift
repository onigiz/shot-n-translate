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
                do {
                    let full = try await captureVisibleDisplay(display)
                    for candidate in [local, appKitLocal] {
                        if let cropped = crop(full, localPoints: candidate, screen: screen) {
                            consider(cropped)
                        }
                        if bestScore >= 0.01 {
                            return best!
                        }
                    }
                } catch {
                    note(error)
                }
            }
            if let window = windowUnderSelection(rect, content: content) {
                do {
                    consider(try await captureWindow(window, selection: rect, scale: screen.backingScaleFactor))
                    if bestScore >= 0.01 {
                        return best!
                    }
                } catch {
                    note(error)
                }
            }
            if let display {
                let filter = contentFilter(for: display, content: content, screenFrame: screen.frame)
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
                if bestScore < 0.01 {
                    do {
                        let full = try await captureFullDisplay(filter: filter, screen: screen)
                        for candidate in [local, appKitLocal] {
                            if let cropped = crop(full, localPoints: candidate, screen: screen) {
                                consider(cropped)
                            }
                            if bestScore >= 0.01 {
                                return best!
                            }
                        }
                    } catch {
                        note(error)
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
            if TextRecognizer.brightPixelFraction(best) < 0.004, !CGPreflightScreenCaptureAccess() {
                throw ScreenCaptureFailure(permissionDenied: true)
            }
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
    /// after Screen Recording has been allowed.
    private static func loadShareableContent() async throws -> SCShareableContent {
        let box = ShareableContentBox()
        await Task.detached(priority: .userInitiated) {
            do {
                box.content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                box.error = error
            }
        }.value
        if let content = box.content {
            return content
        }
        throw box.error ?? ScreenCaptureFailure(permissionDenied: false)
    }

    /// The display capture can return the desktop picture behind every window.
    /// The window under the selection has the page pixels themselves.
    private static func windowUnderSelection(_ rect: CGRect, content: SCShareableContent) -> SCWindow? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let floor = CGWindowLevelForKey(.normalWindow)
        let hits = content.windows.filter { window in
            window.isOnScreen
                && window.frame.contains(center)
                && window.owningApplication?.processID != pid
                && window.windowLayer >= floor
                && window.frame.width >= 40
                && window.frame.height >= 40
        }
        return hits.min { lhs, rhs in
            if lhs.windowLayer != rhs.windowLayer {
                return lhs.windowLayer > rhs.windowLayer
            }
            return lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
    }

    private static func captureWindow(_ window: SCWindow, selection: CGRect, scale: CGFloat) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let measuredScale = CGFloat(filter.pointPixelScale)
        let pointScale = measuredScale > 0 ? measuredScale : max(scale, 1)
        let size = window.frame.size
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(origin: .zero, size: size)
        configuration.width = max(Int((size.width * pointScale).rounded()), 1)
        configuration.height = max(Int((size.height * pointScale).rounded()), 1)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.shouldBeOpaque = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let fromTop = CGRect(
            x: selection.minX - window.frame.minX,
            y: window.frame.height - (selection.maxY - window.frame.minY),
            width: selection.width,
            height: selection.height
        )
        let fromBottom = CGRect(
            x: selection.minX - window.frame.minX,
            y: selection.minY - window.frame.minY,
            width: selection.width,
            height: selection.height
        )
        let choices = [fromTop, fromBottom].compactMap { crop($0, in: image, unitSize: size) } + [image]
        return choices.max { TextRecognizer.brightPixelFraction($0) < TextRecognizer.brightPixelFraction($1) } ?? image
    }

    /// The whole display, as composited, with no source rectangle. A partial
    /// rectangle was coming back as the empty desktop behind the windows.
    private static func captureVisibleDisplay(_ display: SCDisplay) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
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

    private static func captureFullDisplay(filter: SCContentFilter, screen: NSScreen) async throws -> CGImage {
        let measuredScale = CGFloat(filter.pointPixelScale)
        let pointScale = measuredScale > 0 ? measuredScale : max(screen.backingScaleFactor, 1)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(origin: .zero, size: screen.frame.size)
        configuration.width = max(Int((screen.frame.width * pointScale).rounded()), 1)
        configuration.height = max(Int((screen.frame.height * pointScale).rounded()), 1)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.shouldBeOpaque = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private static func crop(_ image: CGImage, localPoints: CGRect, screen: NSScreen) -> CGImage? {
        crop(localPoints, in: image, unitSize: screen.frame.size)
    }

    private static func crop(_ localPoints: CGRect, in image: CGImage, unitSize: CGSize) -> CGImage? {
        let scaleX = CGFloat(image.width) / max(unitSize.width, 1)
        let scaleY = CGFloat(image.height) / max(unitSize.height, 1)
        let rect = CGRect(
            x: localPoints.origin.x * scaleX,
            y: localPoints.origin.y * scaleY,
            width: localPoints.width * scaleX,
            height: localPoints.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return nil }
        return image.cropping(to: rect)
    }

    private static func captureRect(_ rect: CGRect) async throws -> CGImage {
        try await SCScreenshotManager.captureImage(in: rect)
    }

    private static func contentFilter(
        for display: SCDisplay,
        content: SCShareableContent,
        screenFrame: CGRect
    ) -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        let floor = CGWindowLevelForKey(.normalWindow)
        let windows = content.windows.filter { window in
            window.isOnScreen
                && window.frame.intersects(screenFrame)
                && window.owningApplication?.processID != pid
                && window.windowLayer >= floor
        }
        if windows.isEmpty {
            return SCContentFilter(display: display, excludingWindows: [])
        }
        return SCContentFilter(display: display, including: windows)
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
