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
        if let direct = try? recognizeAvailable(in: image), !direct.text.isEmpty {
            return direct
        }
        // A tall or very wide capture makes each line a small fraction of the
        // image, or too large for one request. The same text is readable in a
        // short selection. Bands keep each line large enough for Vision.
        let prepared = scaledIfWide(image)
        if prepared.width != image.width,
           let scaled = try? recognizeAvailable(in: prepared), !scaled.text.isEmpty {
            return scaled
        }
        let bands = recognizeInHorizontalBands(prepared)
        if !bands.text.isEmpty {
            return bands
        }
        return RecognizedText(text: "")
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
        let drawn = samplesByDrawing(image)
        if let drawn, drawn.contains(where: { $0 >= 160 }) {
            return drawn
        }
        return samplesFromBuffer(image) ?? drawn
    }

    /// ScreenCaptureKit images are 32-bit BGRA. Drawing them into an RGBA context
    /// produces a black image, so Vision then reports that the page has no text.
    public static func standardImage(_ image: CGImage) -> CGImage {
        guard let rendered = draw(image, width: image.width, height: image.height) else {
            return image
        }
        if brightPixelFraction(rendered) + 0.005 < brightPixelFraction(image) {
            return image
        }
        return rendered
    }

    private static func samplesByDrawing(_ image: CGImage) -> [UInt8]? {
        guard let rendered = draw(image, width: 64, height: 64) else { return nil }
        return samplesFromBuffer(rendered)
    }

    private static func draw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let bitmapInfos: [UInt32] = [
            CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue,
            CGImageAlphaInfo.noneSkipLast.rawValue
        ]
        var best: CGImage?
        var bestPeak = -1
        for bitmapInfo in bitmapInfos {
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                continue
            }
            context.interpolationQuality = width == image.width ? .none : .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let rendered = context.makeImage() else { continue }
            let peak = samplesFromBuffer(rendered)?.max().map(Int.init) ?? 0
            if peak > bestPeak {
                best = rendered
                bestPeak = peak
            }
        }
        return best
    }

    private static func samplesFromBuffer(_ image: CGImage) -> [UInt8]? {
        guard image.bitsPerComponent == 8,
              let data = image.dataProvider?.data,
              let base = CFDataGetBytePtr(data) else {
            return nil
        }
        let length = CFDataGetLength(data)
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 3, image.bytesPerRow >= image.width * bytesPerPixel else {
            return nil
        }
        var samples: [UInt8] = []
        let stepX = max(image.width / 64, 1)
        let stepY = max(image.height / 64, 1)
        for y in stride(from: 0, to: image.height, by: stepY) {
            for x in stride(from: 0, to: image.width, by: stepX) {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                guard offset + 2 < length else { continue }
                samples.append(max(base[offset], base[offset + 1], base[offset + 2]))
            }
        }
        return samples.isEmpty ? nil : samples
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
        // The default is about 1/32 of the image. Zero is ignored and falls back
        // to that default, which drops body text in a tall selection. A small
        // explicit fraction stays in effect.
        request.minimumTextHeight = 0.004
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

    /// Tries the accurate and fast recognizers. One thrown request does not
    /// hide a later pass that can still read the image.
    private static func recognizeAvailable(in image: CGImage) throws -> RecognizedText? {
        let attempts: [(VNRequestTextRecognitionLevel, [String]?)] = [
            (.accurate, nil),
            (.accurate, fallbackRecognitionLanguages),
            (.fast, fallbackRecognitionLanguages)
        ]
        var sawResult = false
        var lastError: Error?
        for attempt in attempts {
            do {
                let recognized = try recognize(in: image, level: attempt.0, recognitionLanguages: attempt.1)
                sawResult = true
                if !recognized.text.isEmpty {
                    return recognized
                }
            } catch {
                lastError = error
            }
        }
        if let boosted = boostedContrast(image) {
            do {
                let recognized = try recognize(
                    in: boosted,
                    level: .accurate,
                    recognitionLanguages: fallbackRecognitionLanguages
                )
                sawResult = true
                if !recognized.text.isEmpty {
                    return recognized
                }
            } catch {
                lastError = error
            }
        }
        if !sawResult, let lastError {
            throw lastError
        }
        return nil
    }

    /// Retina captures of a wide window are large enough that one Vision request
    /// returns no text. The text stays readable at this width.
    private static func scaledIfWide(_ image: CGImage) -> CGImage {
        let maxWidth = 2000
        guard image.width > maxWidth else { return image }
        let scale = Double(maxWidth) / Double(image.width)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        return draw(image, width: maxWidth, height: height) ?? image
    }

    private static func recognizeInHorizontalBands(_ image: CGImage) -> RecognizedText {
        let bandHeight = 260
        let overlap = 36
        guard image.height > bandHeight else {
            return (try? recognizeAvailable(in: image)) ?? RecognizedText(text: "")
        }
        var lines: [String] = []
        var y = 0
        while y < image.height {
            let height = min(bandHeight, image.height - y)
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let rect = CGRect(x: 0, y: y, width: image.width, height: height).integral.intersection(bounds)
            if rect.width >= 1, rect.height >= 1, let band = image.cropping(to: rect) {
                let recognized = recognizeBand(band)
                for line in recognized.text.split(separator: "\n", omittingEmptySubsequences: true) {
                    let text = String(line)
                    if lines.suffix(3).contains(text) {
                        continue
                    }
                    lines.append(text)
                }
            }
            if y + height >= image.height {
                break
            }
            y += bandHeight - overlap
        }
        return RecognizedText(text: lines.joined(separator: "\n"))
    }

    private static func recognizeBand(_ image: CGImage) -> RecognizedText {
        if let recognized = try? recognize(
            in: image,
            level: .accurate,
            recognitionLanguages: fallbackRecognitionLanguages
        ), !recognized.text.isEmpty {
            return recognized
        }
        if let boosted = boostedContrast(image),
           let recognized = try? recognize(
               in: boosted,
               level: .accurate,
               recognitionLanguages: fallbackRecognitionLanguages
           ), !recognized.text.isEmpty {
            return recognized
        }
        return (try? recognize(in: image, level: .fast, recognitionLanguages: fallbackRecognitionLanguages))
            ?? RecognizedText(text: "")
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
