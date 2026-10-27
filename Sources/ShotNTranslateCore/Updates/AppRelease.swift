import Foundation

public enum VersionRelation: Equatable, Sendable {
    case newer
    case current
    case older
}

public func versionRelation(of release: SemanticVersion, to installed: SemanticVersion) -> VersionRelation {
    if release == installed { return .current }
    if release > installed { return .newer }
    return .older
}

public struct AppRelease: Identifiable, Equatable, Hashable, Sendable {
    public var version: SemanticVersion
    public var publishedAt: Date?
    /// English patch notes, shown as published. The app does not translate them.
    public var notes: String
    public var downloadURL: URL?
    public var releaseURL: URL?

    public var id: String { version.description }

    public init(
        version: SemanticVersion,
        publishedAt: Date?,
        notes: String,
        downloadURL: URL?,
        releaseURL: URL?
    ) {
        self.version = version
        self.publishedAt = publishedAt
        self.notes = notes
        self.downloadURL = downloadURL
        self.releaseURL = releaseURL
    }
}

public enum UpdateFailure: Error, Equatable, Sendable {
    case repositoryNotAccessible
    case invalidResponse
    case updatesRequireAppBundle
    case noDownloadablePackage
    case untrustedDownloadURL
    case archiveDoesNotContainApp
    case downloadFailed
    case installFailed
}

public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case loaded
    case downloading
    case installing
    case failed(UpdateFailure)
}
