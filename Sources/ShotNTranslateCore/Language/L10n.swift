import Foundation

public enum L10nKey: CaseIterable, Sendable {
    case translationTarget
    case targetTurkish
    case targetEnglish
    case sourceDetectedAutomatically
    case appLanguage
    case languageOptionTurkish
    case languageOptionEnglish
    case checkForUpdates
    case updateHistory
    case updateHistoryTitle
    case quit
    case youAreUpToDate
    case updateAvailable
    case noPublishedVersions
    case installUpdate
    case restoreVersion
    case installed
    case patchNotes
    case patchNotesLanguageCaption
    case noPatchNotes
    case checking
    case downloading
    case installing
    case couldNotCheck
    case repositoryNotAccessible
    case invalidResponse
    case updatesRequireAppBundle
    case noDownloadablePackage
    case untrustedDownloadURL
    case archiveDoesNotContainApp
    case downloadFailed
    case installFailed
    case confirmUpdateTitle
    case confirmRestoreTitle
    case continueAction
    case cancel
    case openReleasePage
}

public enum L10n {
    public static func string(_ key: L10nKey, language: AppLanguage) -> String {
        switch language {
        case .turkish:
            turkish(key)
        case .english:
            english(key)
        }
    }

    public static func installedVersionLine(_ version: String, language: AppLanguage) -> String {
        switch language {
        case .turkish:
            "Yüklü sürüm: \(version)"
        case .english:
            "Installed version: \(version)"
        }
    }

    public static func menuUpdateAvailable(version: String, language: AppLanguage) -> String {
        switch language {
        case .turkish:
            "Yeni sürüm var: \(version)"
        case .english:
            "A new version is available: \(version)"
        }
    }

    public static func confirmUpdateMessage(version: String, language: AppLanguage) -> String {
        switch language {
        case .turkish:
            "Uygulama \(version) sürümüne güncellenecek."
        case .english:
            "The app will update to \(version)."
        }
    }

    public static func confirmRestoreMessage(version: String, language: AppLanguage) -> String {
        switch language {
        case .turkish:
            "Uygulama \(version) sürümüne geri dönecek."
        case .english:
            "The app will restore \(version)."
        }
    }

    public static func failure(_ failure: UpdateFailure, language: AppLanguage) -> String {
        switch failure {
        case .repositoryNotAccessible:
            string(.repositoryNotAccessible, language: language)
        case .invalidResponse:
            string(.invalidResponse, language: language)
        case .updatesRequireAppBundle:
            string(.updatesRequireAppBundle, language: language)
        case .noDownloadablePackage:
            string(.noDownloadablePackage, language: language)
        case .untrustedDownloadURL:
            string(.untrustedDownloadURL, language: language)
        case .archiveDoesNotContainApp:
            string(.archiveDoesNotContainApp, language: language)
        case .downloadFailed:
            string(.downloadFailed, language: language)
        case .installFailed:
            string(.installFailed, language: language)
        }
    }

    private static func turkish(_ key: L10nKey) -> String {
        switch key {
        case .translationTarget: "Çeviri hedefi"
        case .targetTurkish: "Türkçe"
        case .targetEnglish: "İngilizce"
        case .sourceDetectedAutomatically: "Kaynak dil otomatik tespit edilir"
        case .appLanguage: "Uygulama dili"
        case .languageOptionTurkish: "Türkçe"
        case .languageOptionEnglish: "English"
        case .checkForUpdates: "Güncellemeleri denetle"
        case .updateHistory: "Güncelleme geçmişi…"
        case .updateHistoryTitle: "Güncelleme geçmişi"
        case .quit: "Çıkış"
        case .youAreUpToDate: "Güncelsiniz"
        case .updateAvailable: "Yeni sürüm var"
        case .noPublishedVersions: "Henüz yayımlanmış sürüm yok."
        case .installUpdate: "Güncelle"
        case .restoreVersion: "Bu sürüme dön"
        case .installed: "Yüklü"
        case .patchNotes: "Yama notları"
        case .patchNotesLanguageCaption: "Yama notları İngilizce yayımlanır."
        case .noPatchNotes: "Bu sürüm için yama notu yok."
        case .checking: "Denetleniyor…"
        case .downloading: "İndiriliyor…"
        case .installing: "Kuruluyor… Güncellemeden sonra uygulama yeniden açılır."
        case .couldNotCheck: "Güncellemeler denetlenemedi."
        case .repositoryNotAccessible: "Sürüm listesine erişilemedi."
        case .invalidResponse: "Sürüm listesi okunamadı."
        case .updatesRequireAppBundle: "Güncelleme yalnızca kurulu uygulama paketinden yapılır."
        case .noDownloadablePackage: "Bu sürümde indirilebilir paket yok."
        case .untrustedDownloadURL: "İndirme adresi güvenilir değil."
        case .archiveDoesNotContainApp: "Paketin içinde uygulama yok."
        case .downloadFailed: "İndirme başarısız oldu."
        case .installFailed: "Kurulum başarısız oldu."
        case .confirmUpdateTitle: "Güncelleme kurulsun mu?"
        case .confirmRestoreTitle: "Bu sürüme dönülsün mü?"
        case .continueAction: "Devam et"
        case .cancel: "Vazgeç"
        case .openReleasePage: "Sürüm sayfasını aç"
        }
    }

    private static func english(_ key: L10nKey) -> String {
        switch key {
        case .translationTarget: "Translation target"
        case .targetTurkish: "Turkish"
        case .targetEnglish: "English"
        case .sourceDetectedAutomatically: "Source language is detected automatically"
        case .appLanguage: "App language"
        case .languageOptionTurkish: "Türkçe"
        case .languageOptionEnglish: "English"
        case .checkForUpdates: "Check for Updates"
        case .updateHistory: "Update History…"
        case .updateHistoryTitle: "Update History"
        case .quit: "Quit"
        case .youAreUpToDate: "You are up to date"
        case .updateAvailable: "A new version is available"
        case .noPublishedVersions: "No published versions yet."
        case .installUpdate: "Update"
        case .restoreVersion: "Restore this version"
        case .installed: "Installed"
        case .patchNotes: "Patch notes"
        case .patchNotesLanguageCaption: "Patch notes are published in English."
        case .noPatchNotes: "No patch notes for this version."
        case .checking: "Checking…"
        case .downloading: "Downloading…"
        case .installing: "Installing… The app reopens after the update."
        case .couldNotCheck: "Could not check for updates."
        case .repositoryNotAccessible: "Could not reach the release list."
        case .invalidResponse: "The release list could not be read."
        case .updatesRequireAppBundle: "Updates install only from the application bundle."
        case .noDownloadablePackage: "This version has no downloadable package."
        case .untrustedDownloadURL: "The download address is not trusted."
        case .archiveDoesNotContainApp: "The package does not contain the app."
        case .downloadFailed: "The download failed."
        case .installFailed: "The installation failed."
        case .confirmUpdateTitle: "Install this update?"
        case .confirmRestoreTitle: "Restore this version?"
        case .continueAction: "Continue"
        case .cancel: "Cancel"
        case .openReleasePage: "Open release page"
        }
    }
}
