import Foundation
import ShotNTranslateCore
@preconcurrency import Translation

/// Translates with an installed on-device model.
///
/// SwiftUI `.translationTask` can wait forever before it hands over a session,
/// which leaves the preview on Translating. When the language pair is already
/// installed, `TranslationSession(installedSource:target:)` does the work
/// directly. `session.isReady` is not awaited: that call can sit forever even
/// after LanguageAvailability reports the pair as installed. If `translate`
/// never answers, `cancel()` ends it.
@MainActor
enum InstalledTranslation {
    struct Outcome: Sendable {
        var text: String
        var sourceCode: String?
    }

    /// How long one capture may wait on Apple Translation before the preview moves on.
    static let answerLimit: UInt64 = 20_000_000_000

    private static var active: TranslationSession?

    static func isInstalled(source: String, target: String) async -> Bool {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: source),
            to: Locale.Language(identifier: target)
        )
        return status == .installed
    }

    static func track(_ session: TranslationSession) {
        active = session
    }

    static func release(_ session: TranslationSession) {
        if active === session {
            active = nil
        }
    }

    static func cancelActive() {
        active?.cancel()
    }

    static func translate(
        paragraphs: [String],
        sourceCode: String,
        targetCode: String
    ) async -> Outcome? {
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: sourceCode),
            target: Locale.Language(identifier: targetCode)
        )
        track(session)
        defer { release(session) }
        do {
            try Task.checkCancellation()
            try await session.prepareTranslation()
            var pieces: [String] = []
            var detected: String?
            for paragraph in paragraphs {
                try Task.checkCancellation()
                let response = try await session.translate(paragraph)
                if detected == nil {
                    detected = response.sourceLanguage.languageCode?.identifier
                        ?? response.sourceLanguage.maximalIdentifier
                }
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !translated.isEmpty {
                    pieces.append(translated)
                }
            }
            let text = pieces.joined(separator: "\n\n")
            guard !text.isEmpty else { return nil }
            return Outcome(text: text, sourceCode: detected)
        } catch {
            return nil
        }
    }
}
