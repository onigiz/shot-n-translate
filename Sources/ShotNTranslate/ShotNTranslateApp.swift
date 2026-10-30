import AppKit
import ShotNTranslateCore
import SwiftUI

@main
struct ShotNTranslateApp: App {
    @State private var languageStore: LanguageStore
    @State private var translationSettings: TranslationSettings
    @State private var updateCenter: UpdateCenter
    @State private var translator: ScreenshotTranslator
    @State private var router: ShortcutRouter
    @State private var cardLibrary: CardLibraryController

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let center = UpdateCenter()
        center.quit = { NSApplication.shared.terminate(nil) }
        let language = LanguageStore.shared
        let settings = TranslationSettings.shared
        let translator = ScreenshotTranslator(settings: settings, languageStore: language)
        let library = CardLibraryController(translator: translator, languageStore: language)
        let router = ShortcutRouter(translator: translator, updateCenter: center)
        router.openUpdateHistory = {
            UpdateHistoryWindow.show(languageStore: language, updateCenter: center)
        }
        router.openCardLibrary = {
            CardLibraryWindow.show(library: library, languageStore: language)
        }
        GlobalShortcutCenter.shared.install(router: router)
        _languageStore = State(initialValue: language)
        _translationSettings = State(initialValue: settings)
        _updateCenter = State(initialValue: center)
        _translator = State(initialValue: translator)
        _router = State(initialValue: router)
        _cardLibrary = State(initialValue: library)
    }

    var body: some Scene {
        MenuBarExtra {
            AppMenu()
                .environment(languageStore)
                .environment(translationSettings)
                .environment(updateCenter)
                .environment(translator)
                .environment(router)
                .environment(cardLibrary)
        } label: {
            Image(systemName: "camera.viewfinder")
                .accessibilityLabel(AppReleaseIdentity.applicationName)
        }
        .menuBarExtraStyle(.menu)

    }
}
