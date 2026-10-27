import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case turkish = "tr"
    case english = "en"

    public var id: String { rawValue }

    /// Language used until the user picks one in the menu.
    /// Change this when the product default should change.
    /// A language already stored on the Mac wins over this value.
    public static let defaultLanguage: AppLanguage = .turkish
}
