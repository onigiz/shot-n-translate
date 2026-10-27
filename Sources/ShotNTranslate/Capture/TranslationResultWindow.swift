import AppKit
import ShotNTranslateCore
import SwiftUI
@preconcurrency import Translation

@MainActor
enum TranslationResultWindow {
    private static var window: NSWindow?

    static func show(translator: ScreenshotTranslator, languageStore: LanguageStore) {
        if window == nil {
            let controller = NSHostingController(rootView: TranslationResultView()
                .environment(translator)
                .environment(languageStore))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.title = L10n.string(.translationResultTitle, language: languageStore.language)
            window.contentMinSize = NSSize(width: 420, height: 280)
            window.setContentSize(NSSize(width: 560, height: 480))
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.level = .normal
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
                ProgressView(L10n.string(.readingSelection, language: language))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure(let key):
                ScrollView {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            L10n.string(key, language: language),
                            systemImage: "exclamationmark.triangle"
                        )
                        .frame(maxWidth: .infinity, minHeight: 160)
                        if let preview = translator.capturePreview {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.string(.capturedRegion, language: language))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(nsImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 280)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
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
            do {
                try await session.prepareTranslation()
                let response = try await session.translate(text)
                let sourceCode = response.sourceLanguage.languageCode?.identifier
                    ?? response.sourceLanguage.maximalIdentifier
                translator.finishTranslation(
                    of: text,
                    translated: response.targetText,
                    detectedSourceCode: sourceCode
                )
            } catch {
                translator.finishTranslation(of: text, translated: nil, detectedSourceCode: nil)
            }
        }
    }

    private func resultBody(_ result: CaptureTranslation, language: AppLanguage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let code = result.sourceLanguageCode {
                    LabeledContent(L10n.string(.detectedLanguage, language: language)) {
                        Text(languageName(code, ui: language))
                    }
                }
                if let note = result.note {
                    Text(L10n.string(noteKey(note), language: language))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                textSection(.originalText, text: result.original, language: language)
                if translator.isTranslating {
                    ProgressView(L10n.string(.translating, language: language))
                }
                if let translated = result.translatedText {
                    textSection(.translationResult, text: translated, language: language)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func textSection(_ key: L10nKey, text: String, language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(key, language: language))
                .font(.headline)
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func noteKey(_ note: CaptureTranslation.Note) -> L10nKey {
        switch note {
        case .alreadyInTargetLanguage: .alreadyInTargetLanguage
        case .languageNotDetected: .languageNotDetected
        case .translationUnavailable: .translationUnavailable
        }
    }

    private func languageName(_ code: String, ui: AppLanguage) -> String {
        let locale = Locale(identifier: ui.rawValue)
        return locale.localizedString(forLanguageCode: code)
            ?? locale.localizedString(forIdentifier: code)
            ?? code
    }
}
