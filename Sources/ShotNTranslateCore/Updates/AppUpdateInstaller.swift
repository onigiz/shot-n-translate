import Foundation
import os

public struct AppUpdateInstaller: Sendable {
    public var bundleURL: @Sendable () -> URL?
    public var download: @Sendable (URL) async throws -> URL
    public var relaunch: @Sendable (_ stagedApp: URL, _ destination: URL) throws -> Void

    public init(
        bundleURL: @escaping @Sendable () -> URL?,
        download: @escaping @Sendable (URL) async throws -> URL,
        relaunch: @escaping @Sendable (_ stagedApp: URL, _ destination: URL) throws -> Void
    ) {
        self.bundleURL = bundleURL
        self.download = download
        self.relaunch = relaunch
    }

    public static let live = AppUpdateInstaller(
        bundleURL: { InstalledApplication.bundleURL },
        download: { try await ReleaseDownloader.download($0) },
        relaunch: { try AppRelauncher.swapAndRelaunch(stagedApp: $0, destination: $1) }
    )

    public func install(release: AppRelease) async throws {
        guard let destination = bundleURL(), destination.pathExtension == "app" else {
            throw UpdateFailure.updatesRequireAppBundle
        }
        guard let sourceURL = release.downloadURL else {
            throw UpdateFailure.noDownloadablePackage
        }
        guard ReleaseAssetPolicy.isOfficialDownloadURL(sourceURL) else {
            throw UpdateFailure.untrustedDownloadURL
        }

        let downloaded = try await download(sourceURL)
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("snt-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        do {
            try ZipExtractor.extract(zip: downloaded, to: workspace)
        } catch {
            throw UpdateFailure.installFailed
        }
        let extracted = try AppArchive.locateApplication(in: workspace)
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("snt-staged-\(UUID().uuidString).app")
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
        try FileManager.default.copyItem(at: extracted, to: staged)
        try relaunch(staged, destination)
    }
}

enum InstalledApplication {
    static var bundleURL: URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return nil }
        return url
    }
}

public enum AppArchive {
    public static func locateApplication(
        in root: URL,
        preferredName: String = AppReleaseIdentity.applicationName
    ) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            throw UpdateFailure.archiveDoesNotContainApp
        }
        var found: [URL] = []
        for case let item as URL in enumerator {
            if item.pathExtension == "app" {
                found.append(item)
                enumerator.skipDescendants()
            }
        }
        if let preferred = found.first(where: {
            $0.deletingPathExtension().lastPathComponent == preferredName
        }) {
            return preferred
        }
        if found.count == 1 {
            return found[0]
        }
        throw UpdateFailure.archiveDoesNotContainApp
    }
}

enum ZipExtractor {
    static func extract(zip: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateFailure.installFailed
        }
    }
}

public enum ReleaseDownloader {
    public static func download(_ url: URL) async throws -> URL {
        let delegate = ReleaseDownloadRedirects()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("ShotNTranslate", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let token = GitHubCLISession.token(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let fileURL: URL
        let response: URLResponse
        do {
            (fileURL, response) = try await session.download(for: request)
        } catch {
            throw UpdateFailure.downloadFailed
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateFailure.downloadFailed
        }
        guard let finalURL = response.url, ReleaseAssetPolicy.isAllowedFinalURL(finalURL) else {
            throw UpdateFailure.untrustedDownloadURL
        }
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: fileURL, to: kept)
        } catch {
            throw UpdateFailure.downloadFailed
        }
        return kept
    }
}

private final class ReleaseDownloadRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, ReleaseAssetPolicy.isAllowedFinalURL(url) else {
            completionHandler(nil)
            return
        }
        var cleaned = request
        let host = url.host?.lowercased()
        if host != "github.com" && host != "api.github.com" {
            cleaned.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(cleaned)
    }
}

public enum AppRelauncher {
    public static let script = """
    set -euo pipefail
    pid="$1"
    source_app="$2"
    destination_app="$3"
    while kill -0 "$pid" 2>/dev/null; do
      sleep 0.2
    done
    parent="$(dirname "$destination_app")"
    name="$(basename "$destination_app")"
    temporary="$parent/.$name.updating"
    rm -rf "$temporary"
    ditto "$source_app" "$temporary"
    rm -rf "$destination_app"
    mv "$temporary" "$destination_app"
    xattr -dr com.apple.quarantine "$destination_app" || true
    rm -rf "$source_app"
    open "$destination_app"
    """

    static func swapAndRelaunch(stagedApp: URL, destination: URL) throws {
        guard destination.pathExtension == "app" else {
            throw UpdateFailure.updatesRequireAppBundle
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            script,
            "update",
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path,
            destination.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Logger(subsystem: AppReleaseIdentity.bundleIdentifier, category: "updates")
                .error("Could not start the update helper")
            throw UpdateFailure.installFailed
        }
    }
}
