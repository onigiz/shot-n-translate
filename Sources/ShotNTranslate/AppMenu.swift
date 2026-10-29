import AppKit
import ShotNTranslateCore
import SwiftUI

struct AppMenu: View {
    @Environment(LanguageStore.self) private var languageStore
    @Environment(TranslationSettings.self) private var translationSettings
    @Environment(UpdateCenter.self) private var updateCenter
    @Environment(ScreenshotTranslator.self) private var translator
    @Environment(ShortcutRouter.self) private var router

    var body: some View {
        let language = languageStore.language

        Button(AppReleaseIdentity.applicationName) {}
            .disabled(true)
        Button(L10n.installedVersionLine(updateCenter.current.display, language: language)) {}
            .disabled(true)

        if let newest = updateCenter.newestUpdate {
            Button(L10n.menuUpdateAvailable(version: newest.version.description, language: language)) {
                showUpdateHistory()
            }
        } else if case .loaded = updateCenter.status {
            Button(L10n.string(.youAreUpToDate, language: language)) {}
                .disabled(true)
        } else if case .checking = updateCenter.status {
            Button(L10n.string(.checking, language: language)) {}
                .disabled(true)
        } else if case .failed = updateCenter.status {
            Button(L10n.string(.couldNotCheck, language: language)) {}
                .disabled(true)
        }

        Divider()

        Button(L10n.string(.translateSelection, language: language)) {
            router.run(.translateSelection)
        }
        .disabled(translator.isBusy)

        Menu(L10n.string(.shortcutsMenu, language: language)) {
            ForEach(ShortcutCatalog.items) { spec in
                Button(shortcutTitle(spec.function, language: language)) {
                    router.run(spec.function)
                }
                .keyboardShortcut(KeyEquivalent(Character(spec.key)), modifiers: shortcutModifiers(spec))
                .disabled(isShortcutDisabled(spec.function))
            }
        }

        Divider()

        Section(L10n.string(.translationTarget, language: language)) {
            targetToggle(.turkish, title: L10n.string(.targetTurkish, language: language), language: language)
            targetToggle(.english, title: L10n.string(.targetEnglish, language: language), language: language)
        }
        Button(L10n.string(.sourceDetectedAutomatically, language: language)) {}
            .disabled(true)

        Divider()

        Section(L10n.string(.translationArea, language: language)) {
            scopeToggle(.immediate, title: L10n.string(.translateImmediately, language: language), language: language)
            scopeToggle(.regionFirst, title: L10n.string(.selectRegionFirst, language: language), language: language)
        }
        Button(L10n.string(.selectEntireImageShortcut, language: language)) {}
            .disabled(true)

        Divider()

        Section(L10n.string(.appLanguage, language: language)) {
            languageToggle(.turkish, title: L10n.string(.languageOptionTurkish, language: language))
            languageToggle(.english, title: L10n.string(.languageOptionEnglish, language: language))
        }

        Divider()

        Button(L10n.string(.checkForUpdates, language: language)) {
            showUpdateHistory()
        }
        .disabled(updateCenter.isBusy)
        Button(L10n.string(.updateHistory, language: language)) {
            showUpdateHistory(checking: false)
        }

        Divider()

        Button(L10n.string(.quit, language: language)) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func shortcutTitle(_ function: ShortcutFunction, language: AppLanguage) -> String {
        switch function {
        case .translateSelection:
            L10n.string(.translateSelection, language: language)
        case .checkForUpdates:
            L10n.string(.checkForUpdates, language: language)
        case .showUpdateHistory:
            L10n.string(.updateHistory, language: language)
        }
    }

    private func shortcutModifiers(_ spec: ShortcutSpec) -> EventModifiers {
        var modifiers: EventModifiers = []
        if spec.command { modifiers.insert(.command) }
        if spec.shift { modifiers.insert(.shift) }
        return modifiers
    }

    private func isShortcutDisabled(_ function: ShortcutFunction) -> Bool {
        switch function {
        case .translateSelection:
            translator.isBusy
        case .checkForUpdates:
            updateCenter.isBusy
        case .showUpdateHistory:
            false
        }
    }

    private func targetToggle(_ target: TranslationTarget, title: String, language: AppLanguage) -> some View {
        Toggle(isOn: Binding(
            get: { translationSettings.target == target },
            set: { isOn in
                if isOn { translationSettings.target = target }
            }
        )) {
            Text(title)
        }
        .accessibilityLabel(title)
        .id("\(language.rawValue)-\(target.rawValue)")
    }

    private func scopeToggle(_ scope: TranslationScope, title: String, language: AppLanguage) -> some View {
        Toggle(isOn: Binding(
            get: { translationSettings.scope == scope },
            set: { isOn in
                if isOn { translationSettings.scope = scope }
            }
        )) {
            Text(title)
        }
        .accessibilityLabel(title)
        .id("\(language.rawValue)-scope-\(scope.rawValue)")
    }

    private func languageToggle(_ choice: AppLanguage, title: String) -> some View {
        Toggle(isOn: Binding(
            get: { languageStore.language == choice },
            set: { isOn in
                if isOn { languageStore.language = choice }
            }
        )) {
            Text(title)
        }
    }

    private func showUpdateHistory(checking: Bool = true) {
        router.showUpdateHistory(checking: checking)
    }
}
