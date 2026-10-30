import AppKit
import ShotNTranslateCore
import SwiftUI

struct CardLibraryView: View {
    @Environment(CardLibraryController.self) private var library
    @Environment(LanguageStore.self) private var languageStore
    @State private var renaming: LibraryCardSummary?
    @State private var renameText = ""
    @State private var hoveredID: URL?

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 16)
    ]

    var body: some View {
        let language = languageStore.language
        VStack(alignment: .leading, spacing: 12) {
            toolbar(language: language)
            if let notice = library.notice {
                Text(L10n.string(notice, language: language))
                    .foregroundStyle(.red)
            }
            if library.folderPath == nil {
                ContentUnavailableView {
                    Label(
                        L10n.string(.cardLibraryEmptyFolder, language: language),
                        systemImage: "folder.badge.plus"
                    )
                } description: {
                    Text(L10n.string(.cardLibraryChoosePrompt, language: language))
                } actions: {
                    Button(L10n.string(.chooseCardLibraryFolder, language: language)) {
                        library.chooseFolder()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.cards.isEmpty {
                ContentUnavailableView(
                    L10n.string(.cardLibraryNoCards, language: language),
                    systemImage: "rectangle.stack",
                    description: Text(L10n.string(.cardLibraryNoCardsHint, language: language))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(library.cards) { card in
                            cardCell(card, language: language)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            L10n.string(.renameCard, language: language),
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )
        ) {
            TextField(L10n.string(.cardName, language: language), text: $renameText)
            Button(L10n.string(.cancel, language: language), role: .cancel) {
                renaming = nil
            }
            Button(L10n.string(.continueAction, language: language)) {
                if let renaming {
                    library.rename(renaming, to: renameText)
                }
                self.renaming = nil
            }
        }
    }

    private func toolbar(language: AppLanguage) -> some View {
        HStack(spacing: 10) {
            Button {
                library.chooseFolder()
            } label: {
                Label(
                    library.folderPath == nil
                        ? L10n.string(.chooseCardLibraryFolder, language: language)
                        : L10n.string(.changeCardLibraryFolder, language: language),
                    systemImage: "folder"
                )
            }
            if let path = library.folderPath {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Picker(L10n.string(.cardSort, language: language), selection: Binding(
                get: { library.sort },
                set: { library.sort = $0 }
            )) {
                ForEach(CardSort.allCases) { option in
                    Text(sortTitle(option, language: language)).tag(option)
                }
            }
            .frame(width: 220)
            Button {
                library.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L10n.string(.refreshCardLibrary, language: language))
        }
    }

    private func cardCell(_ card: LibraryCardSummary, language: AppLanguage) -> some View {
        let hovered = hoveredID == card.packageURL
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(card.editorIsDark ? Color.black.opacity(0.85) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.secondary.opacity(0.25))
                    )
                CardThumbnail(packageURL: card.packageURL)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
            }
            .frame(height: 140)

            Text(card.title)
                .font(.headline)
                .lineLimit(1)

            ScrollView {
                Text(card.previewText.isEmpty ? L10n.string(.cardNoText, language: language) : card.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 72)

            Text(card.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 232, height: 300, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(hovered ? 0.18 : 0.06), radius: hovered ? 12 : 4, y: hovered ? 4 : 1)
        }
        .scaleEffect(hovered ? 1.08 : 1)
        .zIndex(hovered ? 1 : 0)
        .animation(.easeOut(duration: 0.16), value: hovered)
        .onHover { hovering in
            hoveredID = hovering ? card.packageURL : (hoveredID == card.packageURL ? nil : hoveredID)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            library.open(card)
        }
        .contextMenu {
            Button(L10n.string(.openCard, language: language)) {
                library.open(card)
            }
            Button(L10n.string(.renameCard, language: language)) {
                renameText = card.title
                renaming = card
            }
            Divider()
            Button(L10n.string(.deleteCard, language: language), role: .destructive) {
                library.delete(card)
            }
        }
        .help(card.title)
    }

    private func sortTitle(_ sort: CardSort, language: AppLanguage) -> String {
        switch sort {
        case .nameAscending: L10n.string(.cardSortNameAscending, language: language)
        case .nameDescending: L10n.string(.cardSortNameDescending, language: language)
        case .createdNewest: L10n.string(.cardSortCreatedNewest, language: language)
        case .createdOldest: L10n.string(.cardSortCreatedOldest, language: language)
        case .modifiedNewest: L10n.string(.cardSortModifiedNewest, language: language)
        case .modifiedOldest: L10n.string(.cardSortModifiedOldest, language: language)
        }
    }
}

private struct CardThumbnail: View {
    var packageURL: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: packageURL) {
            image = loadThumbnail()
        }
    }

    private func loadThumbnail() -> NSImage? {
        do {
            let capture = try CardPackage.readCapture(at: packageURL)
            let document = try CardPackage.readDocument(at: packageURL)
            let marked = PreviewMarkupImage.image(from: capture, markup: document.previewMarkup)
            let turned = PreviewImageTurn(clockwiseDegrees: document.clockwiseDegrees).image(from: marked)
            let longest = max(turned.width, turned.height)
            let scale = min(1, 360 / CGFloat(max(longest, 1)))
            return NSImage(
                cgImage: turned,
                size: NSSize(
                    width: CGFloat(turned.width) * scale,
                    height: CGFloat(turned.height) * scale
                )
            )
        } catch {
            return nil
        }
    }
}
