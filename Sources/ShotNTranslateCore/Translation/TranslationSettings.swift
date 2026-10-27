import Foundation
import Observation

/// Where recognized text is translated.
/// The source language is always detected from the text. There is no manual source picker.
public enum TranslationTarget: String, CaseIterable, Identifiable, Sendable {
    case turkish = "tr"
    case english = "en"

    public var id: String { rawValue }

    /// Target used until the user picks one in the menu.
    public static let defaultTarget: TranslationTarget = .turkish
}

@MainActor
@Observable
public final class TranslationSettings {
    public static let storageKey = "translationTarget"
    public static let shared = TranslationSettings()

    /// The screenshot pipeline reads this when it translates recognized text.
    public var target: TranslationTarget {
        didSet { defaults.set(target.rawValue, forKey: Self.storageKey) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.storageKey),
           let stored = TranslationTarget(rawValue: raw) {
            target = stored
        } else {
            target = .defaultTarget
        }
    }
}
