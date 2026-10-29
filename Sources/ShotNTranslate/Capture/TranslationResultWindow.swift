import AppKit
import ShotNTranslateCore
import SwiftUI
@preconcurrency import Translation

@MainActor
enum TranslationResultWindow {
    private static var window: NSWindow?
    private static let closeDelegate = PreviewWindowDelegate()

    static func hideWithoutReleasing() {
        window?.orderOut(nil)
    }

    static func show(translator: ScreenshotTranslator, languageStore: LanguageStore) {
        if window == nil {
            let controller = NSHostingController(rootView: TranslationResultView()
                .environment(translator)
                .environment(languageStore))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.title = L10n.string(.translationResultTitle, language: languageStore.language)
            window.contentMinSize = NSSize(width: 420, height: 360)
            window.setContentSize(NSSize(width: 640, height: 720))
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.level = .normal
            closeDelegate.onClose = { [weak translator] in
                translator?.releasePreview()
            }
            window.delegate = closeDelegate
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private final class PreviewWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

struct TranslationResultView: View {
    @Environment(ScreenshotTranslator.self) private var translator
    @Environment(LanguageStore.self) private var languageStore

    var body: some View {
        let language = languageStore.language
        Group {
            switch translator.presentation {
            case .idle, .working:
                previewStack {
                    ProgressView(L10n.string(.readingSelection, language: language))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .failure(let key):
                ScrollView {
                    VStack(spacing: 16) {
                        if let preview = translator.capturePreview {
                            Image(nsImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            chooseRegionButton(language: language)
                        }
                        if key == .screenRecordingDenied {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text(L10n.string(.screenRecordingDeniedTitle, language: language))
                                .font(.title2.weight(.semibold))
                                .multilineTextAlignment(.center)
                            Text(L10n.string(.screenRecordingDenied, language: language))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(spacing: 10) {
                                Button(L10n.string(.resetScreenRecordingPermission, language: language)) {
                                    ScreenRecordingAccess.resetGrant()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                Button(L10n.string(.relaunchApp, language: language)) {
                                    ScreenRecordingAccess.relaunch()
                                }
                                .controlSize(.large)
                                Button(L10n.string(.openScreenRecordingSettings, language: language)) {
                                    ScreenRecordingAccess.openSettings()
                                }
                            }
                            .padding(.top, 4)
                        } else {
                            ContentUnavailableView(
                                L10n.string(key, language: language),
                                systemImage: "exclamationmark.triangle"
                            )
                            .frame(maxWidth: .infinity, minHeight: 160)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            case .result(let result):
                resultBody(result, language: language)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
        .background(WindowTitleSetter(title: L10n.string(.translationResultTitle, language: language)))
        .translationTask(translator.translationConfiguration) { session in
            let text = translator.textWaitingForTranslation()
            guard let text else { return }
            let generation = translator.currentTranslationID
            do {
                try await session.prepareTranslation()
                let response = try await session.translate(text)
                let sourceCode = response.sourceLanguage.languageCode?.identifier
                    ?? response.sourceLanguage.maximalIdentifier
                translator.finishTranslation(
                    of: text,
                    generation: generation,
                    translated: response.targetText,
                    detectedSourceCode: sourceCode
                )
            } catch {
                translator.finishTranslation(
                    of: text,
                    generation: generation,
                    translated: nil,
                    detectedSourceCode: nil
                )
            }
        }
    }

    private func resultBody(_ result: CaptureTranslation, language: AppLanguage) -> some View {
        VStack(spacing: 12) {
            if let preview = translator.capturePreview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            chooseRegionButton(language: language)
            sourceMenu(result: result, language: language)
            if translator.isTranslating {
                ProgressView(L10n.string(.translating, language: language))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if translator.draft.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let note = result.note {
                Text(L10n.string(noteKey(note), language: language))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                editor(language: language)
            }
            Divider()
            HStack(spacing: 12) {
                if let notice = translator.saveNotice {
                    Text(L10n.string(notice, language: language))
                        .foregroundStyle(notice == .pdfSaved ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                Button(L10n.string(.savePDF, language: language)) {
                    translator.savePDF()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!translator.canSaveFormattedPDF)
            }
        }
    }

    private func editor(language: AppLanguage) -> some View {
        VStack(spacing: 8) {
            editorToolbar(language: language)
            TranslationTextEditor(
                text: translator.draft,
                reloadToken: translator.draftToken,
                isDark: translator.editorIsDark,
                controller: translator.editing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.35))
            )
        }
    }

    private func editorToolbar(language: AppLanguage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                formatButton("bold", help: .bold, language: language) {
                    translator.editing.toggleTrait(.boldFontMask)
                }
                formatButton("italic", help: .italic, language: language) {
                    translator.editing.toggleTrait(.italicFontMask)
                }
                formatButton("underline", help: .underline, language: language) {
                    translator.editing.toggleUnderline()
                }
                Divider().frame(height: 16)
                formatButton("text.alignleft", help: .alignLeading, language: language) {
                    translator.editing.align(.left)
                }
                formatButton("text.aligncenter", help: .alignCenter, language: language) {
                    translator.editing.align(.center)
                }
                formatButton("text.alignright", help: .alignTrailing, language: language) {
                    translator.editing.align(.right)
                }
                Divider().frame(height: 16)
                formatButton("textformat.size.smaller", help: .smallerText, language: language) {
                    translator.editing.changeSize(by: -1)
                }
                formatButton("textformat.size.larger", help: .largerText, language: language) {
                    translator.editing.changeSize(by: 1)
                }
                Menu {
                    ForEach(EditorColorChoices.all) { choice in
                        Button(L10n.string(choice.key, language: language)) {
                            translator.editing.apply(color: choice.color)
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.string(.textColor, language: language))
                Divider().frame(height: 16)
                Picker(L10n.string(.editorLight, language: language), selection: Binding(
                    get: { translator.editorIsDark },
                    set: { translator.setEditorSurface(isDark: $0) }
                )) {
                    Text(L10n.string(.editorLight, language: language)).tag(false)
                    Text(L10n.string(.editorDark, language: language)).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .labelsHidden()
            }
        }
    }

    private func formatButton(
        _ symbol: String,
        help: L10nKey,
        language: AppLanguage,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(L10n.string(help, language: language))
    }

    private func previewStack<Below: View>(
        @ViewBuilder below: () -> Below
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let preview = translator.capturePreview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                below()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseRegionButton(language: AppLanguage) -> some View {
        Button(L10n.string(.selectTranslationArea, language: language)) {
            Task { await translator.retranslateSelectedRegion() }
        }
        .disabled(translator.isBusy || translator.isTranslating || translator.capturePreview == nil)
    }

    private func sourceMenu(result: CaptureTranslation, language: AppLanguage) -> some View {
        let selected = result.sourceLanguageCode.map(LanguageDetector.baseCode)
        return HStack(spacing: 8) {
            Text(L10n.string(.sourceLanguage, language: language))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(translator.sourceChoices(selected: selected), id: \.self) { code in
                    Button {
                        translator.useSource(code)
                    } label: {
                        if code == selected {
                            Label(languageName(code, ui: language), systemImage: "checkmark")
                        } else {
                            Text(languageName(code, ui: language))
                        }
                    }
                }
            } label: {
                Text(selected.map { languageName($0, ui: language) } ?? L10n.string(.sourceDetectedAutomatically, language: language))
            }
            .fixedSize()
            Spacer()
        }
    }

    private func languageName(_ code: String, ui: AppLanguage) -> String {
        let locale = Locale(identifier: ui.rawValue)
        return locale.localizedString(forLanguageCode: code)
            ?? locale.localizedString(forIdentifier: code)
            ?? code
    }

    private func noteKey(_ note: CaptureTranslation.Note) -> L10nKey {
        switch note {
        case .alreadyInTargetLanguage: .alreadyInTargetLanguage
        case .languageNotDetected: .languageNotDetected
        case .translationUnavailable: .translationUnavailable
        }
    }

}
