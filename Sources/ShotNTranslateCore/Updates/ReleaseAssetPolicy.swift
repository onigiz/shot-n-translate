import Foundation

public enum ReleaseAssetPolicy {
    public static func isOfficialDownloadURL(
        _ url: URL,
        owner: String = AppReleaseIdentity.githubOwner,
        repository: String = AppReleaseIdentity.githubRepository
    ) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased()
        else {
            return false
        }
        if host == "github.com" {
            let prefix = "/\(owner)/\(repository)/releases/download/"
            return url.path.hasPrefix(prefix) && url.path.lowercased().hasSuffix(".zip")
        }
        if host == "api.github.com" {
            let prefix = "/repos/\(owner)/\(repository)/releases/assets/"
            let identifier = url.path.dropFirst(prefix.count)
            return url.path.hasPrefix(prefix) && !identifier.isEmpty && identifier.allSatisfy(\.isNumber)
        }
        return false
    }

    public static func isAllowedFinalURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased()
        else {
            return false
        }
        let allowed = [
            "github.com",
            "release-assets.githubusercontent.com",
            "objects.githubusercontent.com"
        ]
        return allowed.contains(host)
    }
}
