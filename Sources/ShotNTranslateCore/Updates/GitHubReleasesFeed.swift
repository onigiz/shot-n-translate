import Foundation

public enum ReleaseFeedError: Error, Equatable {
    case repositoryNotAccessible
    case invalidResponse
}

public protocol ReleaseFetching: Sendable {
    func fetch() async throws -> [AppRelease]
}

public struct GitHubReleasesFeed: ReleaseFetching, Sendable {
    public var owner: String
    public var repository: String
    public var session: URLSession

    public init(
        owner: String = AppReleaseIdentity.githubOwner,
        repository: String = AppReleaseIdentity.githubRepository,
        session: URLSession = .shared
    ) {
        self.owner = owner
        self.repository = repository
        self.session = session
    }

    public func fetch() async throws -> [AppRelease] {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases?per_page=100") else {
            throw ReleaseFeedError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("ShotNTranslate", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReleaseFeedError.invalidResponse
        }
        guard let http = response as? HTTPURLResponse else {
            throw ReleaseFeedError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            return try Self.parse(data)
        case 401, 403, 404:
            throw ReleaseFeedError.repositoryNotAccessible
        default:
            throw ReleaseFeedError.invalidResponse
        }
    }

    public static func parse(_ data: Data) throws -> [AppRelease] {
        let decoder = JSONDecoder()
        let payloads: [GitHubReleasePayload]
        do {
            payloads = try decoder.decode([GitHubReleasePayload].self, from: data)
        } catch {
            throw ReleaseFeedError.invalidResponse
        }
        let releases = payloads.compactMap(AppRelease.init(payload:))
        return releases.sorted { lhs, rhs in
            if lhs.version != rhs.version { return lhs.version > rhs.version }
            return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
        }
    }
}

private struct GitHubReleasePayload: Decodable {
    var tagName: String
    var body: String?
    var draft: Bool
    var prerelease: Bool
    var publishedAt: String?
    var htmlURL: String?
    var assets: [Asset]

    struct Asset: Decodable {
        var id: Int
        var name: String
        var browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case draft
        case prerelease
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case assets
    }
}

private extension AppRelease {
    init?(payload: GitHubReleasePayload) {
        guard !payload.draft, !payload.prerelease, let version = SemanticVersion(parsing: payload.tagName) else {
            return nil
        }
        let download = payload.assets.preferredDownloadURL()
        self.init(
            version: version,
            publishedAt: payload.publishedAt.flatMap(GitHubDateParser.date(from:)),
            notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            downloadURL: download,
            releaseURL: payload.htmlURL.flatMap(URL.init(string:))
        )
    }
}

private extension Array where Element == GitHubReleasePayload.Asset {
    func preferredDownloadURL() -> URL? {
        let zips = filter { $0.name.lowercased().hasSuffix(".zip") }
        guard let preferred = zips.first(where: { $0.name == AppReleaseIdentity.assetName }) ?? zips.first else {
            return nil
        }
        let owner = AppReleaseIdentity.githubOwner
        let repository = AppReleaseIdentity.githubRepository
        return URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/assets/\(preferred.id)")
    }
}

private enum GitHubDateParser {
    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
