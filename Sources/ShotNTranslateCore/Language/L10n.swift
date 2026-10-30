import Foundation

public enum L10nKey: CaseIterable, Sendable {
    case translationTarget
    case targetTurkish
    case targetEnglish
    case sourceDetectedAutomatically
    case sourceLanguage
    case translationArea
    case translateImmediately
    case selectRegionFirst
    case selectEntireImageShortcut
    case selectTranslationArea
    case dragTranslationArea
    case translateSelectedArea
    case translationAreaTitle
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
    case shortcutsMenu
    case translateSelection
    case dragToSelect
    case readingSelection
    case translating
    case noTextFound
    case capturedRegion
    case detectedLanguage
    case originalText
    case translationResult
    case translationResultTitle
    case alreadyInTargetLanguage
    case languageNotDetected
    case translationUnavailable
    case screenRecordingDenied
    case screenRecordingDeniedTitle
    case resetScreenRecordingPermission
    case openScreenRecordingSettings
    case relaunchApp
    case captureFailed
    case recognitionFailed
    case savePDF
    case pdfSaved
    case pdfSaveFailed
    case pdfFileName
    case bold
    case italic
    case underline
    case alignLeading
    case alignCenter
    case alignTrailing
    case textColor
    case largerText
    case smallerText
    case editorLight
    case editorDark
    case rotateImageHandle
    case cropImage
    case drawSquare
    case drawCircle
    case shapeColor
    case shapeThickness
    case undoMark
    case resetCrop
    case colorBlack
    case colorWhite
    case colorRed
    case colorOrange
    case colorGreen
    case colorBlue
    case cardLibrary
    case cardLibraryTitle
    case chooseCardLibraryFolder
    case changeCardLibraryFolder
    case cardLibraryEmptyFolder
    case cardLibraryChoosePrompt
    case cardLibraryNoCards
    case cardLibraryNoCardsHint
    case cardLibraryLoadFailed
    case refreshCardLibrary
    case cardSort
    case cardSortNameAscending
    case cardSortNameDescending
    case cardSortCreatedNewest
    case cardSortCreatedOldest
    case cardSortModifiedNewest
    case cardSortModifiedOldest
    case saveCard
    case cardSaved
    case cardSaveFailed
    case openCard
    case renameCard
    case deleteCard
    case cardName
    case cardNoText
    case cardOpenFailed
    case cardRenameFailed
    case cardDeleteFailed
    case cardTitleTaken
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
        case .sourceLanguage: "Kaynak dil"
        case .translationArea: "Çeviri alanı"
        case .translateImmediately: "Doğrudan çevir"
        case .selectRegionFirst: "Önce bölge seç"
        case .selectEntireImageShortcut: "Bölge seçerken ⌘A tüm görseli seçer"
        case .selectTranslationArea: "Çevrilecek bölgeyi seç"
        case .dragTranslationArea: "Çevrilecek alanı sürükleyin. Tüm görsel için ⌘A. Vazgeçmek için Esc."
        case .translateSelectedArea: "Seçilen alanı çevir"
        case .translationAreaTitle: "Çevrilecek alan"
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
        case .shortcutsMenu: "Kısayollar"
        case .translateSelection: "Bölgeyi çevir"
        case .dragToSelect: "Yazıyı seçmek için sürükleyin. Vazgeçmek için Esc."
        case .readingSelection: "Yazı okunuyor…"
        case .translating: "Çevriliyor…"
        case .noTextFound: "Bu bölgede yazı bulunamadı."
        case .capturedRegion: "Yakalanan bölge"
        case .detectedLanguage: "Tespit edilen dil"
        case .originalText: "Orijinal"
        case .translationResult: "Çeviri"
        case .translationResultTitle: "Çeviri sonucu"
        case .alreadyInTargetLanguage: "Metin zaten hedef dilde."
        case .languageNotDetected: "Yazının dili tespit edilemedi."
        case .translationUnavailable: "Bu dil çifti için çeviri kullanılamıyor. Sistem Ayarları'ndan çeviri dilini indirin."
        case .screenRecordingDeniedTitle: "Ekran kaydı izni gerekli"
        case .screenRecordingDenied: "Bu kopyaya henüz izin verilmedi. Anahtar açık görünse bile macOS eski izni tutuyor olabilir. Önce İzni Sıfırla'ya basın. Açılan pencerede mavi Reddet'e değil Sistem Ayarları'nı Aç'a basın, Shot n Translate anahtarını açın, sonra Kapatıp Yeniden Aç'a basın."
        case .resetScreenRecordingPermission: "İzni Sıfırla"
        case .openScreenRecordingSettings: "Ekran Kaydı Ayarlarını Aç"
        case .relaunchApp: "Kapatıp Yeniden Aç"
        case .captureFailed: "Ekran görüntüsü alınamadı."
        case .recognitionFailed: "Yazı okunamadı."
        case .savePDF: "PDF olarak kaydet"
        case .pdfSaved: "PDF kaydedildi."
        case .pdfSaveFailed: "PDF kaydedilemedi."
        case .pdfFileName: "Ceviri.pdf"
        case .bold: "Kalın"
        case .italic: "İtalik"
        case .underline: "Altı çizili"
        case .alignLeading: "Sola hizala"
        case .alignCenter: "Ortala"
        case .alignTrailing: "Sağa hizala"
        case .textColor: "Metin rengi"
        case .largerText: "Yazıyı büyüt"
        case .smallerText: "Yazıyı küçült"
        case .editorLight: "Açık zemin"
        case .editorDark: "Koyu zemin"
        case .rotateImageHandle: "Tutamacı sürükleyerek görseli döndür. Merkez yerinde kalır."
        case .cropImage: "Görseli kırp"
        case .drawSquare: "Kare çiz"
        case .drawCircle: "Çember çiz"
        case .shapeColor: "Şekil rengi"
        case .shapeThickness: "Çerçeve kalınlığı"
        case .undoMark: "Son şekli sil"
        case .resetCrop: "Kırpmayı geri al"
        case .colorBlack: "Siyah"
        case .colorWhite: "Beyaz"
        case .colorRed: "Kırmızı"
        case .colorOrange: "Turuncu"
        case .colorGreen: "Yeşil"
        case .colorBlue: "Mavi"
        case .cardLibrary: "Kart kütüphanesi…"
        case .cardLibraryTitle: "Kart kütüphanesi"
        case .chooseCardLibraryFolder: "Kütüphane klasörünü seç"
        case .changeCardLibraryFolder: "Klasörü değiştir"
        case .cardLibraryEmptyFolder: "Henüz bir kütüphane klasörü yok"
        case .cardLibraryChoosePrompt: "Kartların kaydedileceği klasörü seçin. Sonra çevirileri buradan açıp düzenleyebilirsiniz."
        case .cardLibraryNoCards: "Bu klasörde kart yok"
        case .cardLibraryNoCardsHint: "Bir çeviriyi kaydettiğinizde burada kart olarak görünür."
        case .cardLibraryLoadFailed: "Kart kütüphanesi okunamadı."
        case .refreshCardLibrary: "Kütüphaneyi yenile"
        case .cardSort: "Sıralama"
        case .cardSortNameAscending: "Ada göre (A→Z)"
        case .cardSortNameDescending: "Ada göre (Z→A)"
        case .cardSortCreatedNewest: "Oluşturma (yeni→eski)"
        case .cardSortCreatedOldest: "Oluşturma (eski→yeni)"
        case .cardSortModifiedNewest: "Değiştirme (yeni→eski)"
        case .cardSortModifiedOldest: "Değiştirme (eski→yeni)"
        case .saveCard: "Kütüphaneye kaydet"
        case .cardSaved: "Kart kütüphaneye kaydedildi."
        case .cardSaveFailed: "Kart kaydedilemedi."
        case .openCard: "Kartı aç"
        case .renameCard: "Kartı yeniden adlandır"
        case .deleteCard: "Kartı sil"
        case .cardName: "Kart adı"
        case .cardNoText: "Metin yok"
        case .cardOpenFailed: "Kart açılamadı."
        case .cardRenameFailed: "Kart yeniden adlandırılamadı."
        case .cardDeleteFailed: "Kart silinemedi."
        case .cardTitleTaken: "Bu adla bir kart zaten var."
        }
    }

    private static func english(_ key: L10nKey) -> String {
        switch key {
        case .translationTarget: "Translation target"
        case .targetTurkish: "Turkish"
        case .targetEnglish: "English"
        case .sourceDetectedAutomatically: "Source language is detected automatically"
        case .sourceLanguage: "Source language"
        case .translationArea: "Translation area"
        case .translateImmediately: "Translate immediately"
        case .selectRegionFirst: "Select a region first"
        case .selectEntireImageShortcut: "While selecting a region, ⌘A selects the whole image"
        case .selectTranslationArea: "Select area to translate"
        case .dragTranslationArea: "Drag the area to translate. Press ⌘A for the whole image. Press Esc to cancel."
        case .translateSelectedArea: "Translate selected area"
        case .translationAreaTitle: "Area to translate"
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
        case .shortcutsMenu: "Shortcuts"
        case .translateSelection: "Translate Selection"
        case .dragToSelect: "Drag to select the text. Press Esc to cancel."
        case .readingSelection: "Reading text…"
        case .translating: "Translating…"
        case .noTextFound: "No text was found in this region."
        case .capturedRegion: "Captured region"
        case .detectedLanguage: "Detected language"
        case .originalText: "Original"
        case .translationResult: "Translation"
        case .translationResultTitle: "Translation Result"
        case .alreadyInTargetLanguage: "The text is already in the target language."
        case .languageNotDetected: "The language of the text could not be detected."
        case .translationUnavailable: "Translation is not available for this language pair. Download the language in System Settings."
        case .screenRecordingDeniedTitle: "Screen Recording permission required"
        case .screenRecordingDenied: "This copy is not granted yet. The switch can stay on while macOS keeps an old grant. Click Reset Permission once. In the system dialog, choose Open System Settings — not the blue Deny button — turn Shot n Translate on, then Quit and Reopen."
        case .resetScreenRecordingPermission: "Reset Permission"
        case .openScreenRecordingSettings: "Open Screen Recording Settings"
        case .relaunchApp: "Quit and Reopen"
        case .captureFailed: "The screenshot could not be captured."
        case .recognitionFailed: "The text could not be read."
        case .savePDF: "Save as PDF"
        case .pdfSaved: "The PDF was saved."
        case .pdfSaveFailed: "The PDF could not be saved."
        case .pdfFileName: "Translation.pdf"
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .alignLeading: "Align left"
        case .alignCenter: "Center"
        case .alignTrailing: "Align right"
        case .textColor: "Text color"
        case .largerText: "Larger text"
        case .smallerText: "Smaller text"
        case .editorLight: "Light background"
        case .editorDark: "Dark background"
        case .rotateImageHandle: "Drag the handle to rotate the image. The center stays fixed."
        case .cropImage: "Crop image"
        case .drawSquare: "Draw a square"
        case .drawCircle: "Draw a circle"
        case .shapeColor: "Shape color"
        case .shapeThickness: "Outline thickness"
        case .undoMark: "Remove last shape"
        case .resetCrop: "Reset crop"
        case .colorBlack: "Black"
        case .colorWhite: "White"
        case .colorRed: "Red"
        case .colorOrange: "Orange"
        case .colorGreen: "Green"
        case .colorBlue: "Blue"
        case .cardLibrary: "Card Library…"
        case .cardLibraryTitle: "Card Library"
        case .chooseCardLibraryFolder: "Choose library folder"
        case .changeCardLibraryFolder: "Change folder"
        case .cardLibraryEmptyFolder: "No library folder yet"
        case .cardLibraryChoosePrompt: "Choose the folder where cards are stored. You can open and edit translations from there later."
        case .cardLibraryNoCards: "No cards in this folder"
        case .cardLibraryNoCardsHint: "When you save a translation, it appears here as a card."
        case .cardLibraryLoadFailed: "The card library could not be read."
        case .refreshCardLibrary: "Refresh library"
        case .cardSort: "Sort"
        case .cardSortNameAscending: "Name (A→Z)"
        case .cardSortNameDescending: "Name (Z→A)"
        case .cardSortCreatedNewest: "Created (newest)"
        case .cardSortCreatedOldest: "Created (oldest)"
        case .cardSortModifiedNewest: "Modified (newest)"
        case .cardSortModifiedOldest: "Modified (oldest)"
        case .saveCard: "Save to Library"
        case .cardSaved: "The card was saved to the library."
        case .cardSaveFailed: "The card could not be saved."
        case .openCard: "Open card"
        case .renameCard: "Rename card"
        case .deleteCard: "Delete card"
        case .cardName: "Card name"
        case .cardNoText: "No text"
        case .cardOpenFailed: "The card could not be opened."
        case .cardRenameFailed: "The card could not be renamed."
        case .cardDeleteFailed: "The card could not be deleted."
        case .cardTitleTaken: "A card with that name already exists."
        }
    }
}
