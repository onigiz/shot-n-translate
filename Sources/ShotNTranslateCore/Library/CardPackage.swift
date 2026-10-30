import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CardPackageError: Error, Equatable, CustomStringConvertible {
    case missingLibraryFolder
    case cannotCreatePackage
    case cannotWriteCapture
    case cannotWriteTranslation
    case cannotReadPackage
    case cannotRename
    case titleTaken

    public var description: String {
        switch self {
        case .missingLibraryFolder: "The card library folder is not set."
        case .cannotCreatePackage: "The card package could not be created."
        case .cannotWriteCapture: "The screenshot could not be saved into the card."
        case .cannotWriteTranslation: "The translation could not be saved into the card."
        case .cannotReadPackage: "The card package could not be read."
        case .cannotRename: "The card could not be renamed."
        case .titleTaken: "A card with that name already exists."
        }
    }
}

/// Reads and writes `.sntcard` directory packages in a user-chosen folder.
public enum CardPackage {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func isPackage(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == CardNaming.packageExtension
    }

    public static func list(in folder: URL) throws -> [LibraryCardSummary] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try contents.compactMap { url -> LibraryCardSummary? in
            guard isPackage(url) else { return nil }
            let document = try readDocument(at: url)
            return LibraryCardSummary(
                packageURL: url,
                title: document.title,
                createdAt: document.createdAt,
                modifiedAt: document.modifiedAt,
                previewText: document.previewText,
                editorIsDark: document.editorIsDark
            )
        }
    }

    public static func nextTitle(in folder: URL, on date: Date = Date()) throws -> String {
        let titles = try list(in: folder).map(\.title)
        return CardNaming.nextTitle(existing: titles, on: date)
    }

    public static func write(
        document: CardDocument,
        capture: CGImage,
        translationRTF: Data,
        to packageURL: URL
    ) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: packageURL.path) {
            try manager.removeItem(at: packageURL)
        }
        try manager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let infoURL = packageURL.appendingPathComponent(CardDocument.infoFileName)
        try encoder.encode(document).write(to: infoURL, options: .atomic)
        try writePNG(capture, to: packageURL.appendingPathComponent(CardDocument.captureFileName))
        try translationRTF.write(
            to: packageURL.appendingPathComponent(CardDocument.translationFileName),
            options: .atomic
        )
    }

    public static func readDocument(at packageURL: URL) throws -> CardDocument {
        let infoURL = packageURL.appendingPathComponent(CardDocument.infoFileName)
        let data = try Data(contentsOf: infoURL)
        return try decoder.decode(CardDocument.self, from: data)
    }

    public static func readCapture(at packageURL: URL) throws -> CGImage {
        let url = packageURL.appendingPathComponent(CardDocument.captureFileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CardPackageError.cannotReadPackage
        }
        return image
    }

    public static func readTranslationRTF(at packageURL: URL) throws -> Data {
        try Data(contentsOf: packageURL.appendingPathComponent(CardDocument.translationFileName))
    }

    public static func rename(packageURL: URL, to title: String) throws -> URL {
        let folder = packageURL.deletingLastPathComponent()
        let destination = CardNaming.packageURL(named: title, in: folder)
        if destination.standardizedFileURL == packageURL.standardizedFileURL {
            var document = try readDocument(at: packageURL)
            document.title = title
            document.modifiedAt = Date()
            try encoder.encode(document).write(
                to: packageURL.appendingPathComponent(CardDocument.infoFileName),
                options: .atomic
            )
            return packageURL
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw CardPackageError.titleTaken
        }
        var document = try readDocument(at: packageURL)
        document.title = title
        document.modifiedAt = Date()
        try FileManager.default.moveItem(at: packageURL, to: destination)
        try encoder.encode(document).write(
            to: destination.appendingPathComponent(CardDocument.infoFileName),
            options: .atomic
        )
        return destination
    }

    public static func delete(packageURL: URL) throws {
        try FileManager.default.removeItem(at: packageURL)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CardPackageError.cannotWriteCapture
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CardPackageError.cannotWriteCapture
        }
    }
}
