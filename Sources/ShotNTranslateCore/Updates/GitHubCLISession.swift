import Foundation
import os

/// Reads the GitHub CLI session already stored for this Mac.
/// The token stays in the CLI keychain and is never written into the app.
enum GitHubCLISession {
    private static let cached = OSAllocatedUnfairLock<String?>(initialState: nil)

    static func token() -> String? {
        if let existing = cached.withLock({ $0 }) {
            return existing
        }
        guard let resolved = resolve(), !resolved.isEmpty else { return nil }
        cached.withLock { $0 = resolved }
        return resolved
    }

    private static func resolve() -> String? {
        for path in executableCandidates() where FileManager.default.isExecutableFile(atPath: path) {
            if let token = readToken(at: path) {
                return token
            }
        }
        return nil
    }

    private static func executableCandidates() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/gh",
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh"
        ]
    }

    private static func readToken(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["auth", "token"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else { return nil }
        return token
    }
}
