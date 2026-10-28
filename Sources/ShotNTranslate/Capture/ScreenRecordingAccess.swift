import AppKit
import ShotNTranslateCore

@MainActor
enum ScreenRecordingAccess {
    /// Removes the stored Screen Recording grant and asks once.
    /// A grant made for an older copy stays switched on, and macOS then shows
    /// the system dialog on every capture. That dialog has no Allow button.
    /// Resetting the grant is what lets the switch apply to this copy.
    static func resetGrant() {
        let bundleID = Bundle.main.bundleIdentifier ?? AppReleaseIdentity.bundleIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "ScreenCapture", bundleID]
        if (try? task.run()) != nil {
            task.waitUntilExit()
        }
        openSettings()
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        let panes = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ]
        for pane in panes {
            guard let url = URL(string: pane) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// macOS applies a new Screen Recording grant on the next launch.
    static func relaunch() {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            NSApp.terminate(nil)
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1.2 && open \"$1\"", "sh", appURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
