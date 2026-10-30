import AppKit
import Observation
import ShotNTranslateCore

@MainActor
@Observable
final class CardLibraryController {
    private(set) var cards: [LibraryCardSummary] = []
    private(set) var folderPath: String?
    private(set) var notice: L10nKey?
    private(set) var isBusy = false
    var sort: CardSort {
        didSet {
            folderStore.sort = sort
            cards = sort.sorted(cards)
        }
    }

    private let folderStore: LibraryFolderStore
    private let translator: ScreenshotTranslator
    private let languageStore: LanguageStore

    init(
        translator: ScreenshotTranslator,
        languageStore: LanguageStore,
        folderStore: LibraryFolderStore = .shared
    ) {
        self.translator = translator
        self.languageStore = languageStore
        self.folderStore = folderStore
        sort = folderStore.sort
        folderPath = folderStore.folderURL?.path
    }

    func refresh() {
        notice = nil
        guard let folder = folderStore.startAccessing() else {
            cards = []
            folderPath = nil
            return
        }
        defer { folderStore.stopAccessing() }
        folderPath = folder.path
        do {
            cards = sort.sorted(try CardPackage.list(in: folder))
        } catch {
            cards = []
            notice = .cardLibraryLoadFailed
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.string(.chooseCardLibraryFolder, language: languageStore.language)
        NSApp.activate()
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.folderStore.remember(url)
            self.folderPath = url.path
            self.refresh()
        }
    }

    func open(_ card: LibraryCardSummary) {
        isBusy = true
        defer { isBusy = false }
        do {
            try translator.openCard(at: card.packageURL)
            notice = nil
        } catch {
            notice = .cardOpenFailed
        }
    }

    func rename(_ card: LibraryCardSummary, to title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        do {
            _ = try folderStore.withFolder { _ in
                try CardPackage.rename(packageURL: card.packageURL, to: cleaned)
            }
            refresh()
        } catch CardPackageError.titleTaken {
            notice = .cardTitleTaken
        } catch {
            notice = .cardRenameFailed
        }
    }

    func delete(_ card: LibraryCardSummary) {
        do {
            try folderStore.withFolder { _ in
                try CardPackage.delete(packageURL: card.packageURL)
            }
            refresh()
        } catch {
            notice = .cardDeleteFailed
        }
    }
}
