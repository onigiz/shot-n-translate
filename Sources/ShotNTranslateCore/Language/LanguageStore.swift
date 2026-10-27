import Foundation
import Observation

@MainActor
@Observable
public final class LanguageStore {
    public static let storageKey = "appLanguage"
    public static let shared = LanguageStore()

    public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.storageKey) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.storageKey),
           let stored = AppLanguage(rawValue: raw) {
            language = stored
        } else {
            language = .defaultLanguage
        }
    }
}
