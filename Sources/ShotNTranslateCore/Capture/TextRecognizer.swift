import CoreGraphics
import Vision

public struct RecognizedText: Equatable, Sendable {
    public var text: String
    /// Language codes Vision reported for the recognized lines, most frequent first.
    public var visionLanguageCodes: [String]

    public init(text: String, visionLanguageCodes: [String] = []) {
        self.text = text
        self.visionLanguageCodes = visionLanguageCodes
    }
}

public enum TextRecognizer {
    /// Languages tried when automatic detection returns no observations.
    /// English and Turkish are the product's translation languages.
    private static let fallbackRecognitionLanguages = ["en-US", "tr-TR"]

    public static func recognize(in image: CGImage) throws -> RecognizedText {
        let automatic = try recognize(in: image, recognitionLanguages: nil)
        if !automatic.text.isEmpty {
            return automatic
        }
        do {
            return try recognize(in: image, recognitionLanguages: fallbackRecognitionLanguages)
        } catch {
            return automatic
        }
    }

    private static func recognize(in image: CGImage, recognitionLanguages: [String]?) throws -> RecognizedText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // The default threshold is 1/32 of the image height, so body text in a tall
        // screenshot is discarded and the region looks empty.
        request.minimumTextHeight = 0
        if let recognitionLanguages {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = recognitionLanguages
        } else {
            request.automaticallyDetectsLanguage = true
        }
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        let lines = observations.compactMap { observation -> String? in
            guard let line = observation.topCandidates(1).first?.string else { return nil }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return RecognizedText(text: lines.joined(separator: "\n"))
    }
}
