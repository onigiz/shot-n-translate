import Foundation

/// Remembers the user-chosen card library folder across launches.
public final class LibraryFolderStore: @unchecked Sendable {
    public static let shared = LibraryFolderStore()
    public static let bookmarkStorageKey = "cardLibraryFolderBookmark"
    public static let pathStorageKey = "cardLibraryFolderPath"
    public static let sortStorageKey = "cardLibrarySort"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var accessCount = 0
    private var accessedURL: URL?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var sort: CardSort {
        get {
            guard let raw = defaults.string(forKey: Self.sortStorageKey),
                  let sort = CardSort(rawValue: raw) else {
                return .modifiedNewest
            }
            return sort
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.sortStorageKey)
        }
    }

    public var folderURL: URL? {
        if let bookmark = defaults.data(forKey: Self.bookmarkStorageKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if stale {
                    remember(url)
                }
                return url
            }
        }
        if let path = defaults.string(forKey: Self.pathStorageKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    public func remember(_ url: URL) {
        defaults.set(url.path, forKey: Self.pathStorageKey)
        let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        if let data {
            defaults.set(data, forKey: Self.bookmarkStorageKey)
        } else if let plain = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(plain, forKey: Self.bookmarkStorageKey)
        }
    }

    public func clear() {
        stopAccessing()
        defaults.removeObject(forKey: Self.bookmarkStorageKey)
        defaults.removeObject(forKey: Self.pathStorageKey)
    }

    @discardableResult
    public func startAccessing() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let url = folderURL else { return nil }
        if accessCount == 0 {
            _ = url.startAccessingSecurityScopedResource()
            accessedURL = url
        }
        accessCount += 1
        return url
    }

    public func stopAccessing() {
        lock.lock()
        defer { lock.unlock() }
        guard accessCount > 0 else { return }
        accessCount -= 1
        if accessCount == 0, let url = accessedURL {
            url.stopAccessingSecurityScopedResource()
            accessedURL = nil
        }
    }

    public func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        guard let url = startAccessing() else {
            throw CardPackageError.missingLibraryFolder
        }
        defer { stopAccessing() }
        return try body(url)
    }
}
