import AppKit
import ShotNTranslateCore
import SwiftUI

@main
struct ShotNTranslateApp: App {
    @State private var languageStore: LanguageStore
    @State private var translationSettings: TranslationSettings
    @State private var updateCenter: UpdateCenter

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let center = UpdateCenter()
        center.quit = { NSApplication.shared.terminate(nil) }
        _languageStore = State(initialValue: .shared)
        _translationSettings = State(initialValue: .shared)
        _updateCenter = State(initialValue: center)
    }

    var body: some Scene {
        MenuBarExtra {
            AppMenu()
                .environment(languageStore)
                .environment(translationSettings)
                .environment(updateCenter)
        } label: {
            Image(systemName: "camera.viewfinder")
                .accessibilityLabel(AppReleaseIdentity.applicationName)
        }
        .menuBarExtraStyle(.menu)

        Window(AppReleaseIdentity.applicationName, id: AppWindow.updateHistory) {
            UpdateHistoryView()
                .environment(languageStore)
                .environment(updateCenter)
        }
        .defaultSize(width: 760, height: 520)
    }
}

enum AppWindow {
    static let updateHistory = "update-history"
}
