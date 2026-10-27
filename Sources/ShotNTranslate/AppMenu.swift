import AppKit
import ShotNTranslateCore
import SwiftUI

struct AppMenu: View {
    @Environment(LanguageStore.self) private var languageStore
    @Environment(TranslationSettings.self) private var translationSettings
    @Environment(UpdateCenter.self) private var updateCenter
    @Environment(\.openWindow) private var openWindow

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

        Section(L10n.string(.translationTarget, language: language)) {
            targetToggle(.turkish, title: L10n.string(.targetTurkish, language: language), language: language)
            targetToggle(.english, title: L10n.string(.targetEnglish, language: language), language: language)
        }
        Button(L10n.string(.sourceDetectedAutomatically, language: language)) {}
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
        NSApplication.shared.activate()
        openWindow(id: AppWindow.updateHistory)
        guard checking else { return }
        Task { await updateCenter.checkForUpdates() }
    }
}
