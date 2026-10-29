import Foundation
import Observation

/// Where recognized text is translated.
/// The source language is detected from the text. The preview can correct that source.
public enum TranslationTarget: String, CaseIterable, Identifiable, Sendable {
    case turkish = "tr"
    case english = "en"

    public var id: String { rawValue }

    /// Target used until the user picks one in the menu.
    public static let defaultTarget: TranslationTarget = .turkish
}

/// When the user chooses which part of an already captured screenshot to translate.
/// The screenshot itself is never cropped.
public enum TranslationScope: String, CaseIterable, Identifiable, Sendable {
    /// Read and translate the whole screenshot, then allow a later region.
    case immediate
    /// Ask for a region of the screenshot before the first translation.
    case regionFirst

    public var id: String { rawValue }

    public static let defaultScope: TranslationScope = .immediate
}

@MainActor
@Observable
public final class TranslationSettings {
    public static let storageKey = "translationTarget"
    public static let scopeStorageKey = "translationScope"
    public static let shared = TranslationSettings()

    /// The screenshot pipeline reads this when it translates recognized text.
    public var target: TranslationTarget {
        didSet { defaults.set(target.rawValue, forKey: Self.storageKey) }
    }

    /// Whether the first translation waits for a region of the screenshot.
    public var scope: TranslationScope {
        didSet { defaults.set(scope.rawValue, forKey: Self.scopeStorageKey) }
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
        if let raw = defaults.string(forKey: Self.scopeStorageKey),
           let stored = TranslationScope(rawValue: raw) {
            scope = stored
        } else {
            scope = .defaultScope
        }
    }
}
