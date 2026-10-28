import AppKit

@MainActor
enum ScreenRecordingAccess {
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
        task.arguments = ["-c", "sleep 1 && open -n \"$1\"", "sh", appURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
