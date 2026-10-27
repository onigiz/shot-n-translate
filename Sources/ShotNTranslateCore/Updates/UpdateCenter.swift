import Foundation
import Observation

@MainActor
@Observable
public final class UpdateCenter {
    public var releases: [AppRelease] = []
    public var status: UpdateStatus = .idle
    public var current: AppVersion
    public var quit: @MainActor () -> Void = {}

    private let feed: any ReleaseFetching
    private let installer: AppUpdateInstaller

    public init(
        feed: any ReleaseFetching = GitHubReleasesFeed(),
        installer: AppUpdateInstaller = .live,
        current: AppVersion = AppReleaseIdentity.current
    ) {
        self.feed = feed
        self.installer = installer
        self.current = current
    }

    public var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing:
            true
        case .idle, .loaded, .failed:
            false
        }
    }

    public var newestUpdate: AppRelease? {
        releases.first { relation(of: $0) == .newer }
    }

    public func relation(of release: AppRelease) -> VersionRelation {
        versionRelation(of: release.version, to: current.marketing)
    }

    public func checkForUpdates() async {
        guard !isBusy else { return }
        status = .checking
        do {
            let fetched = try await feed.fetch()
            releases = fetched.sorted { lhs, rhs in
                if lhs.version != rhs.version { return lhs.version > rhs.version }
                return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
            }
            status = .loaded
        } catch let error as ReleaseFeedError {
            releases = []
            switch error {
            case .repositoryNotAccessible:
                status = .failed(.repositoryNotAccessible)
            case .invalidResponse:
                status = .failed(.invalidResponse)
            }
        } catch {
            releases = []
            status = .failed(.invalidResponse)
        }
    }

    public func install(_ release: AppRelease) async {
        guard !isBusy else { return }
        status = .downloading
        do {
            try await installer.install(release: release)
            status = .installing
            quit()
        } catch let failure as UpdateFailure {
            status = .failed(failure)
        } catch {
            status = .failed(.installFailed)
        }
    }
}
