import CoreGraphics
import CoreImage
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
        let image = standardImage(image)
        let automatic = try recognize(in: image, level: .accurate, recognitionLanguages: nil)
        if !automatic.text.isEmpty {
            return automatic
        }
        if let fallback = try? recognize(in: image, level: .accurate, recognitionLanguages: fallbackRecognitionLanguages),
           !fallback.text.isEmpty {
            return fallback
        }
        if let fast = try? recognize(in: image, level: .fast, recognitionLanguages: fallbackRecognitionLanguages),
           !fast.text.isEmpty {
            return fast
        }
        if let boosted = boostedContrast(image),
           let boostedText = try? recognize(in: boosted, level: .accurate, recognitionLanguages: fallbackRecognitionLanguages),
           !boostedText.text.isEmpty {
            return boostedText
        }
        return automatic
    }

    /// Luminance range from 0 to 1. A black permission capture is near 0.
    public static func contrast(_ image: CGImage) -> Double {
        guard let pixels = luminanceSamples(image) else { return 1 }
        var minimum = 255
        var maximum = 0
        for value in pixels {
            let sample = Int(value)
            minimum = min(minimum, sample)
            maximum = max(maximum, sample)
        }
        return Double(maximum - minimum) / 255
    }

    /// Share of samples that are light enough to be body text on a dark page.
    /// A black capture is 0. A dark page with light text is well above that.
    public static func brightPixelFraction(_ image: CGImage) -> Double {
        guard let pixels = luminanceSamples(image), !pixels.isEmpty else { return 0 }
        let bright = pixels.reduce(0) { count, value in
            count + (value >= 160 ? 1 : 0)
        }
        return Double(bright) / Double(pixels.count)
    }

    private static func luminanceSamples(_ image: CGImage) -> [UInt8]? {
        let side = 64
        guard let colorSpace = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ),
              let data = context.data else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side)
        return Array(UnsafeBufferPointer(start: bytes, count: side * side))
    }

    /// ScreenCaptureKit can return wide-gamut or floating-point images. Vision then
    /// reports no text even though the page is visible. Draw into 8-bit sRGB first.
    public static func standardImage(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return image
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func recognize(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        recognitionLanguages: [String]?
    ) throws -> RecognizedText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        if level == .accurate {
            request.usesLanguageCorrection = true
        }
        // One pixel of height. The default is 1/32 of the image, and 0 was ignored
        // by the installed toolchain, so a tall page of body text came back empty.
        request.minimumTextHeight = 1 / Float(max(image.height, 1))
        if let recognitionLanguages {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = recognitionLanguages
        } else if level == .accurate {
            request.automaticallyDetectsLanguage = true
        } else {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = fallbackRecognitionLanguages
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

    /// Light gray body text on a near-black page is valid text. Stretching contrast
    /// gives Vision a last chance after the normal passes return nothing.
    private static func boostedContrast(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(1.6, forKey: kCIInputContrastKey)
        filter.setValue(0.12, forKey: kCIInputBrightnessKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        return context.createCGImage(output, from: output.extent)
    }
}
