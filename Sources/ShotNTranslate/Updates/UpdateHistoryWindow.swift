import AppKit
import ShotNTranslateCore
import SwiftUI

@MainActor
enum UpdateHistoryWindow {
    private static var window: NSWindow?

    static func show(languageStore: LanguageStore, updateCenter: UpdateCenter) {
        if window == nil {
            let controller = NSHostingController(rootView: UpdateHistoryView()
                .environment(languageStore)
                .environment(updateCenter))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.title = L10n.string(.updateHistoryTitle, language: languageStore.language)
            window.contentMinSize = NSSize(width: 680, height: 420)
            window.setContentSize(NSSize(width: 760, height: 520))
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
