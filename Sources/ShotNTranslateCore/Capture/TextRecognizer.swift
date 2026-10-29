import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision
import VisionKit

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

    /// How long an accurate Vision pass may block before a fast pass is tried.
    private static let accurateTimeoutNanoseconds: UInt64 = 12_000_000_000

    /// Scans the screenshot and returns the richest transcript it can read.
    /// Live Text looks at the whole image. Vision also runs in horizontal bands
    /// because a single request measures each line against the full height and
    /// drops body text in a tall capture. Dark captures are inverted and scanned
    /// again when the normal passes find nothing or only a thin result.
    public static func recognize(in image: CGImage) async throws -> RecognizedText {
        let image = standardImage(image)
        var candidates: [RecognizedText] = []

        if let live = try? await liveText(in: image) {
            appendCandidate(live, to: &candidates)
        }
        appendCandidate(
            await visionBandsOffMain(scaledIfWide(image)),
            to: &candidates
        )

        if shouldInvertForOCR(image), let inverted = invertedImage(image) {
            if let live = try? await liveText(in: inverted) {
                appendCandidate(live, to: &candidates)
            }
            appendCandidate(
                await visionBandsOffMain(scaledIfWide(inverted)),
                to: &candidates
            )
        }

        return bestCandidate(candidates) ?? RecognizedText(text: "")
    }

    /// Vision work is synchronous and can stall. Keep it off the main actor.
    private static func visionBandsOffMain(_ image: CGImage) async -> RecognizedText {
        await Task.detached(priority: .userInitiated) {
            await recognizeInHorizontalBands(image)
        }.value
    }

    @MainActor
    private static func liveText(in image: CGImage) async throws -> String {
        let analyzer = ImageAnalyzer()
        let configuration = ImageAnalyzer.Configuration([.text])
        let analysis = try await analyzer.analyze(image, orientation: .up, configuration: configuration)
        return analysis.transcript
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

    /// Mean sample luminance from 0 to 1. Dark UI pages sit well below 0.5.
    public static func meanLuminance(_ image: CGImage) -> Double {
        guard let pixels = luminanceSamples(image), !pixels.isEmpty else { return 1 }
        let total = pixels.reduce(0) { $0 + Int($1) }
        return Double(total) / Double(pixels.count) / 255
    }

    /// Dark pages with real contrast are inverted so Vision sees dark text on light.
    public static func shouldInvertForOCR(_ image: CGImage) -> Bool {
        contrast(image) >= 0.08 && meanLuminance(image) <= 0.45
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
        return RecognizedText(text: TextLayout.transcript(from: lineBoxes(from: request.results ?? [])))
    }

    private static func lineBoxes(from observations: [VNRecognizedTextObservation]) -> [TextLineBox] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return TextLineBox(text: trimmed, bounds: observation.boundingBox)
        }
    }

    /// Tries the accurate and fast recognizers. One thrown request does not
    /// hide a later pass that can still read the image.
    private static func recognizeAvailable(in image: CGImage) async throws -> RecognizedText? {
        let attempts: [(VNRequestTextRecognitionLevel, [String]?)] = [
            (.accurate, nil),
            (.accurate, fallbackRecognitionLanguages),
            (.fast, fallbackRecognitionLanguages)
        ]
        var sawResult = false
        var lastError: Error?
        for attempt in attempts {
            do {
                let recognized = try await recognizeWithTimeout(
                    in: image,
                    level: attempt.0,
                    recognitionLanguages: attempt.1
                )
                sawResult = true
                if !recognized.text.isEmpty {
                    return recognized
                }
            } catch {
                lastError = error
            }
        }
        for variant in [boostedContrast(image), invertedImage(image)].compactMap({ $0 }) {
            do {
                let recognized = try await recognizeWithTimeout(
                    in: variant,
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

    private enum RecognitionTimeout: Error {
        case timedOut
    }

    /// Accurate recognition can stall while macOS compiles the on-device model.
    /// After the timeout, a fast pass still returns text for this capture.
    private static func recognizeWithTimeout(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        recognitionLanguages: [String]?
    ) async throws -> RecognizedText {
        if level != .accurate {
            return try recognize(in: image, level: level, recognitionLanguages: recognitionLanguages)
        }

        do {
            return try await withThrowingTaskGroup(of: RecognizedText.self) { group in
                group.addTask {
                    try await Task.detached(priority: .userInitiated) {
                        try recognize(in: image, level: level, recognitionLanguages: recognitionLanguages)
                    }.value
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: accurateTimeoutNanoseconds)
                    throw RecognitionTimeout.timedOut
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch is RecognitionTimeout {
            return try recognize(
                in: image,
                level: .fast,
                recognitionLanguages: recognitionLanguages ?? fallbackRecognitionLanguages
            )
        }
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

    private static func recognizeInHorizontalBands(_ image: CGImage) async -> RecognizedText {
        let bandHeight = 260
        let overlap = 36
        guard image.height > bandHeight else {
            return (try? await recognizeAvailable(in: image)) ?? RecognizedText(text: "")
        }
        var lines: [TextLineBox] = []
        var y = 0
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        while y < image.height {
            let height = min(bandHeight, image.height - y)
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let rect = CGRect(x: 0, y: y, width: image.width, height: height).integral.intersection(bounds)
            if rect.width >= 1, rect.height >= 1, let band = image.cropping(to: rect) {
                for box in await lineBoxesOffMain(in: band) {
                    lines.append(TextLineBox(
                        text: box.text,
                        bounds: TextLayout.globalBounds(
                            box.bounds,
                            band: rect,
                            imageWidth: imageWidth,
                            imageHeight: imageHeight
                        )
                    ))
                }
            }
            if y + height >= image.height {
                break
            }
            y += bandHeight - overlap
        }
        return RecognizedText(text: TextLayout.transcript(from: lines))
    }

    private static func lineBoxesOffMain(in image: CGImage) async -> [TextLineBox] {
        await Task.detached(priority: .userInitiated) {
            (try? lineBoxes(in: image, level: .accurate, recognitionLanguages: fallbackRecognitionLanguages)) ?? []
        }.value
    }

    private static func lineBoxes(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        recognitionLanguages: [String]?
    ) throws -> [TextLineBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = level == .accurate
        request.minimumTextHeight = 0.004
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = recognitionLanguages ?? fallbackRecognitionLanguages
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        return lineBoxes(from: request.results ?? [])
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

    /// Dark UI / IDE screenshots often OCR better as dark text on a light page.
    public static func invertedImage(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let invert = CIFilter(name: "CIColorInvert") else { return nil }
        invert.setValue(input, forKey: kCIInputImageKey)
        guard let inverted = invert.outputImage else { return nil }
        let context = CIContext(options: nil)
        return context.createCGImage(inverted, from: inverted.extent)
    }

    private static func appendCandidate(_ text: String, to candidates: inout [RecognizedText]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        candidates.append(RecognizedText(text: trimmed))
    }

    private static func appendCandidate(_ recognized: RecognizedText, to candidates: inout [RecognizedText]) {
        let trimmed = recognized.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        candidates.append(RecognizedText(text: trimmed, visionLanguageCodes: recognized.visionLanguageCodes))
    }

    /// More visual lines are not a better transcript. After paragraph preparation,
    /// a line-broken copy of the same words loses to the paragraph form.
    private static func bestCandidate(_ candidates: [RecognizedText]) -> RecognizedText? {
        candidates.reduce(nil) { best, candidate in
            guard let best else { return candidate }
            return TranslationText.isPreferred(candidate.text, over: best.text) ? candidate : best
        }
    }
}
