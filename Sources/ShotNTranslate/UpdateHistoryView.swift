import AppKit
import ShotNTranslateCore
import SwiftUI

struct UpdateHistoryView: View {
    @Environment(LanguageStore.self) private var languageStore
    @Environment(UpdateCenter.self) private var updateCenter
    @State private var selectedID: String?
    @State private var pending: InstallRequest?

    var body: some View {
        let language = languageStore.language
        NavigationSplitView {
            releaseList(language: language)
        } detail: {
            releaseDetail(language: language)
        }
        .navigationTitle(L10n.string(.updateHistoryTitle, language: language))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.string(.checkForUpdates, language: language)) {
                    Task { await updateCenter.checkForUpdates() }
                }
                .disabled(updateCenter.isBusy)
            }
        }
        .background(WindowTitleSetter(title: L10n.string(.updateHistoryTitle, language: language)))
        .onAppear {
            if case .idle = updateCenter.status {
                Task { await updateCenter.checkForUpdates() }
            }
        }
        .onChange(of: updateCenter.releases.map(\.id)) { _, ids in
            if selectedID == nil || (selectedID.map { !ids.contains($0) } ?? false) {
                selectedID = ids.first
            }
        }
        .alert(
            confirmTitle(language: language),
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            presenting: pending
        ) { request in
            Button(L10n.string(.continueAction, language: language)) {
                let release = request.release
                pending = nil
                Task { await updateCenter.install(release) }
            }
            Button(L10n.string(.cancel, language: language), role: .cancel) {}
        } message: { request in
            Text(confirmMessage(request, language: language))
        }
        .frame(minWidth: 680, minHeight: 420)
    }

    private func releaseList(language: AppLanguage) -> some View {
        List(selection: $selectedID) {
            Section(L10n.installedVersionLine(updateCenter.current.display, language: language)) {
                ForEach(updateCenter.releases) { release in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(release.version.description)
                        if let publishedAt = release.publishedAt {
                            Text(publishedAt, format: .dateTime.year().month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(release.id)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }

    @ViewBuilder
    private func releaseDetail(language: AppLanguage) -> some View {
        if let failure = failure {
            ContentUnavailableView {
                Label(L10n.string(.couldNotCheck, language: language), systemImage: "exclamationmark.triangle")
            } description: {
                Text(L10n.failure(failure, language: language))
            }
        } else if updateCenter.status == .checking && updateCenter.releases.isEmpty {
            ProgressView(L10n.string(.checking, language: language))
        } else if updateCenter.releases.isEmpty && updateCenter.status == .loaded {
            ContentUnavailableView(
                L10n.string(.noPublishedVersions, language: language),
                systemImage: "shippingbox"
            )
        } else if let release = selectedRelease {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(release.version.description)
                            .font(.title)
                        Spacer()
                        actionControl(for: release, language: language)
                    }
                    if case .downloading = updateCenter.status {
                        ProgressView(L10n.string(.downloading, language: language))
                    } else if case .installing = updateCenter.status {
                        ProgressView(L10n.string(.installing, language: language))
                    } else if case .failed(let installFailure) = updateCenter.status, !isFeedFailure(installFailure) {
                        Text(L10n.failure(installFailure, language: language))
                            .foregroundStyle(.red)
                    }
                    Text(L10n.string(.patchNotes, language: language))
                        .font(.headline)
                    Text(L10n.string(.patchNotesLanguageCaption, language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    patchNotes(release.notes, language: language)
                    if let releaseURL = release.releaseURL {
                        Link(L10n.string(.openReleasePage, language: language), destination: releaseURL)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ProgressView(L10n.string(.checking, language: language))
        }
    }

    @ViewBuilder
    private func actionControl(for release: AppRelease, language: AppLanguage) -> some View {
        switch updateCenter.relation(of: release) {
        case .newer:
            Button(L10n.string(.installUpdate, language: language)) {
                pending = InstallRequest(kind: .update, release: release)
            }
            .disabled(updateCenter.isBusy || release.downloadURL == nil)
        case .older:
            Button(L10n.string(.restoreVersion, language: language)) {
                pending = InstallRequest(kind: .restore, release: release)
            }
            .disabled(updateCenter.isBusy || release.downloadURL == nil)
        case .current:
            Text(L10n.string(.installed, language: language))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func patchNotes(_ notes: String, language: AppLanguage) -> some View {
        if notes.isEmpty {
            Text(L10n.string(.noPatchNotes, language: language))
                .foregroundStyle(.secondary)
        } else if let attributed = try? AttributedString(markdown: notes) {
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(notes)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedRelease: AppRelease? {
        updateCenter.releases.first { $0.id == selectedID }
    }

    private var failure: UpdateFailure? {
        guard case .failed(let failure) = updateCenter.status, isFeedFailure(failure) else { return nil }
        return failure
    }

    private func isFeedFailure(_ failure: UpdateFailure) -> Bool {
        switch failure {
        case .repositoryNotAccessible, .gitHubSessionMissing, .invalidResponse:
            true
        default:
            false
        }
    }

    private func confirmTitle(language: AppLanguage) -> String {
        switch pending?.kind {
        case .restore:
            L10n.string(.confirmRestoreTitle, language: language)
        default:
            L10n.string(.confirmUpdateTitle, language: language)
        }
    }

    private func confirmMessage(_ request: InstallRequest, language: AppLanguage) -> String {
        switch request.kind {
        case .update:
            L10n.confirmUpdateMessage(version: request.release.version.description, language: language)
        case .restore:
            L10n.confirmRestoreMessage(version: request.release.version.description, language: language)
        }
    }
}

private struct InstallRequest: Identifiable {
    enum Kind {
        case update
        case restore
    }

    var kind: Kind
    var release: AppRelease
    var id: String { "\(kind)-\(release.id)" }
}

private struct WindowTitleSetter: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}
