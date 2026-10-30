import Foundation

public enum ShortcutFunction: String, CaseIterable, Sendable {
    case translateSelection
    case checkForUpdates
    case showUpdateHistory
    case showCardLibrary
}

public struct ShortcutSpec: Equatable, Sendable, Identifiable {
    public var function: ShortcutFunction
    public var key: String
    public var command: Bool
    public var shift: Bool

    public var id: ShortcutFunction { function }

    public init(function: ShortcutFunction, key: String, command: Bool, shift: Bool) {
        self.function = function
        self.key = key
        self.command = command
        self.shift = shift
    }
}

public enum ShortcutCatalog {
    public static let items: [ShortcutSpec] = [
        ShortcutSpec(function: .translateSelection, key: "t", command: true, shift: true),
        ShortcutSpec(function: .checkForUpdates, key: "u", command: true, shift: true),
        ShortcutSpec(function: .showUpdateHistory, key: "h", command: true, shift: true),
        ShortcutSpec(function: .showCardLibrary, key: "l", command: true, shift: true)
    ]
}
