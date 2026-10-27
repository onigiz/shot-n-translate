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
    public static func recognize(in image: CGImage) throws -> RecognizedText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var languageVotes: [String: Int] = [:]
        var lines: [String] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            lines.append(line)
            for language in observation.recognitionLanguages {
                let raw = language.languageCode.map(\.identifier) ?? language.maximalIdentifier
                let base = LanguageDetector.baseCode(raw)
                guard !base.isEmpty, base != "und" else { continue }
                languageVotes[base, default: 0] += 1
            }
        }

        let text = lines.joined(separator: "\n")
        let visionLanguageCodes = languageVotes
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\.key)

        return RecognizedText(text: text, visionLanguageCodes: visionLanguageCodes)
    }
}
