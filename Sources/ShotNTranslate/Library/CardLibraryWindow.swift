import AppKit
import ShotNTranslateCore
import SwiftUI

@MainActor
enum CardLibraryWindow {
    private static var window: NSWindow?

    static func show(library: CardLibraryController, languageStore: LanguageStore) {
        library.refresh()
        if window == nil {
            let controller = NSHostingController(rootView: CardLibraryView()
                .environment(library)
                .environment(languageStore))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.title = L10n.string(.cardLibraryTitle, language: languageStore.language)
            window.contentMinSize = NSSize(width: 720, height: 480)
            window.setContentSize(NSSize(width: 900, height: 620))
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.center()
            self.window = window
        } else {
            window?.title = L10n.string(.cardLibraryTitle, language: languageStore.language)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
