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

    /// Sideways lines below this confidence are not mixed into an upright transcript.
    private static let sidewaysConfidence: Float = 0.4

    private struct VisionRead: Sendable {
        var text: String
        var lines: [TextLineBox]

        static let empty = VisionRead(text: "", lines: [])

        var recognized: RecognizedText {
            RecognizedText(text: text)
        }
    }

    /// Scans the screenshot and returns the richest transcript it can read.
    /// Live Text looks at the whole image. Vision also runs in horizontal bands
    /// because a single request measures each line against the full height and
    /// drops body text in a tall capture. Dark captures are inverted and scanned
    /// again when the normal passes find nothing or only a thin result.
    /// Text lying on its side, upside down, or on a diagonal is read from a turned
    /// copy. The search steps every 5 degrees around the circle. A turned copy is
    /// kept when it contains words the upright pass missed.
    public static func recognize(in image: CGImage) async throws -> RecognizedText {
        let image = standardImage(image)
        let upright = try await recognizeUpright(in: image)
        let text = await resolvedTranscript(for: image, upright: upright)
        return RecognizedText(text: text, visionLanguageCodes: upright.recognized.visionLanguageCodes)
    }

    private static func recognizeUpright(in image: CGImage) async throws -> VisionRead {
        var candidates: [RecognizedText] = []
        var lines: [TextLineBox] = []

        if let live = try? await liveText(in: image) {
            appendCandidate(live, to: &candidates)
        }
        let vision = await visionBandsOffMain(scaledIfWide(image))
        appendCandidate(vision.recognized, to: &candidates)
        lines.append(contentsOf: vision.lines)

        if shouldInvertForOCR(image), let inverted = invertedImage(image) {
            if let live = try? await liveText(in: inverted) {
                appendCandidate(live, to: &candidates)
            }
            let invertedVision = await visionBandsOffMain(scaledIfWide(inverted))
            appendCandidate(invertedVision.recognized, to: &candidates)
            lines.append(contentsOf: invertedVision.lines)
        }

        return VisionRead(
            text: bestCandidate(candidates)?.text ?? "",
            lines: lines
        )
    }

    /// Vision work is synchronous and can stall. Keep it off the main actor.
    private static func visionBandsOffMain(_ image: CGImage) async -> VisionRead {
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
    ) throws -> VisionRead {
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
        let lines = lineBoxes(from: request.results ?? [])
        return VisionRead(text: TextLayout.transcript(from: lines), lines: lines)
    }

    private static func lineBoxes(from observations: [VNRecognizedTextObservation]) -> [TextLineBox] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return TextLineBox(text: trimmed, bounds: observation.boundingBox, confidence: candidate.confidence)
        }
    }

    /// Tries the accurate and fast recognizers. One thrown request does not
    /// hide a later pass that can still read the image.
    private static func recognizeAvailable(in image: CGImage) async throws -> VisionRead? {
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
    ) async throws -> VisionRead {
        if level != .accurate {
            return try recognize(in: image, level: level, recognitionLanguages: recognitionLanguages)
        }

        do {
            return try await withThrowingTaskGroup(of: VisionRead.self) { group in
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

    private static func recognizeInHorizontalBands(_ image: CGImage) async -> VisionRead {
        let bandHeight = 260
        let overlap = 36
        guard image.height > bandHeight else {
            return (try? await recognizeAvailable(in: image)) ?? .empty
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
                        ),
                        confidence: box.confidence
                    ))
                }
            }
            if y + height >= image.height {
                break
            }
            y += bandHeight - overlap
        }
        return VisionRead(text: TextLayout.transcript(from: lines), lines: lines)
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

    private struct PageReading: Sendable {
        var text: String
        var confidence: Float
        var lines: [TextLineBox]
    }

    /// Reads text that is sideways, upside down, or diagonal. The stored screenshot is not rotated.
    /// The search steps every 5 degrees. A turned copy replaces the upright transcript when it
    /// recovers whole words. A label in a free area is appended.
    private static func resolvedTranscript(for image: CGImage, upright: VisionRead) async -> String {
        let uprightText = upright.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard contrast(image) >= 0.08 else { return uprightText }
        let uprightConfidence: Float = upright.lines.isEmpty ? 0.7 : meanConfidence(upright.lines)
        var body = uprightText
        var bodyLines = upright.lines
        var bodyScore = SidewaysText.wordScore(body, confidence: uprightConfidence)
        var extras: [PageReading] = []

        var sources: [CGImage] = [image]
        if shouldInvertForOCR(image), let inverted = invertedImage(image) {
            sources = [inverted, image]
        }
        for source in sources {
            let turns = await orientedReadings(
                of: source,
                original: image,
                uprightScore: bodyScore,
                uprightLines: bodyLines
            )
            for turn in turns {
                let score = SidewaysText.wordScore(turn.text, confidence: turn.confidence)
                if score > bodyScore * 1.15 {
                    if !body.isEmpty {
                        extras.append(PageReading(text: body, confidence: uprightConfidence, lines: bodyLines))
                    }
                    body = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    bodyLines = turn.lines
                    bodyScore = score
                } else {
                    extras.append(turn)
                }
            }
            if bodyScore > SidewaysText.wordScore(uprightText, confidence: uprightConfidence) * 1.15 {
                break
            }
        }

        var combined = body
        for extra in extras {
            let kept = nonOverlapping(extra.lines, avoiding: bodyLines)
            guard !kept.isEmpty else { continue }
            let addition = SidewaysText.addition(TextLayout.transcript(from: kept), upright: combined)
            guard !addition.isEmpty else { continue }
            combined = combined.isEmpty ? addition : combined + "\n\n" + addition
            bodyLines.append(contentsOf: kept)
        }
        return combined
    }

    private enum ScanTurn: Sendable {
        case quarter(ImageQuarterTurn)
        case free(ImageFreeRotation)

        func boundsInOriginal(_ bounds: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
            switch self {
            case .quarter(let turn):
                turn.boundsInOriginal(bounds, originalWidth: width, originalHeight: height)
            case .free(let rotation):
                rotation.boundsInOriginal(bounds, originalWidth: width, originalHeight: height)
            }
        }
    }

    private static func orientedReadings(
        of source: CGImage,
        original: CGImage,
        uprightScore: Float,
        uprightLines: [TextLineBox]
    ) async -> [PageReading] {
        var bestTurn: ScanTurn?
        var bestScore: Float = 0
        var bestReading = PageReading(text: "", confidence: 0, lines: [])

        func consider(_ turn: ScanTurn, _ reading: PageReading) {
            let score = SidewaysText.wordScore(reading.text, confidence: reading.confidence)
            if score > bestScore {
                bestScore = score
                bestTurn = turn
                bestReading = reading
            }
        }

        let cardinals = await Task.detached(priority: .userInitiated) {
            cardinalScans(of: source)
        }.value
        let cardinalReadings = await fastProbe(cardinals, original: original)
        for (index, reading) in cardinalReadings.enumerated() where index < cardinals.count {
            consider(cardinals[index].0, reading)
        }

        let degrees = ImageRotationSweep.probeDegrees
        let batchSize = 8
        var offset = 0
        while offset < degrees.count {
            let batch = Array(degrees[offset..<min(offset + batchSize, degrees.count)])
            let pairs = await Task.detached(priority: .userInitiated) {
                probeScans(of: source, degrees: batch)
            }.value
            let readings = await fastProbe(pairs, original: original)
            for (index, reading) in readings.enumerated() where index < pairs.count {
                consider(pairs[index].0, reading)
            }
            offset += batchSize
        }

        guard bestScore > 0, let bestTurn else { return [] }
        let novel = !nonOverlapping(bestReading.lines, avoiding: uprightLines).isEmpty
        let worthKeeping = uprightScore == 0 || bestScore > uprightScore * 0.9 || (novel && bestScore >= 16)
        guard worthKeeping else { return [] }
        guard let refined = render(bestTurn, from: source, maxSide: 1600) else {
            return [bestReading]
        }
        let accurate = await pageReading(
            refined,
            level: .accurate,
            turn: bestTurn,
            original: original,
            includeLiveText: true
        )
        let accurateScore = SidewaysText.wordScore(accurate.text, confidence: accurate.confidence)
        return [accurateScore >= bestScore ? accurate : bestReading]
    }

    private static func fastProbe(
        _ pairs: [(ScanTurn, CGImage)],
        original: CGImage
    ) async -> [PageReading] {
        guard !pairs.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, PageReading).self) { group in
            for (index, pair) in pairs.enumerated() {
                group.addTask {
                    let reading = await pageReading(
                        pair.1,
                        level: .fast,
                        turn: pair.0,
                        original: original,
                        includeLiveText: false
                    )
                    return (index, reading)
                }
            }
            var output = Array(repeating: PageReading(text: "", confidence: 0, lines: []), count: pairs.count)
            for await (index, reading) in group where index < output.count {
                output[index] = reading
            }
            return output
        }
    }

    /// Quarter turns cover both sideways directions. A half turn covers upside-down text.
    private static func cardinalScans(of source: CGImage) -> [(ScanTurn, CGImage)] {
        var scans: [(ScanTurn, CGImage)] = []
        for turn in [ImageQuarterTurn.clockwise, .counterClockwise] {
            if let turned = turn.image(from: source) {
                scans.append((.quarter(turn), scaledDown(turned, maxSide: 1200)))
            }
        }
        let half = ImageFreeRotation(radians: .pi)
        if let turned = half.image(from: source) {
            scans.append((.free(half), scaledDown(turned, maxSide: 1200)))
        }
        return scans
    }

    /// Every remaining 5 degree step. The fast probe uses a smaller image; the winner is read again at full size.
    private static func probeScans(of source: CGImage, degrees: [Int]) -> [(ScanTurn, CGImage)] {
        degrees.compactMap { degrees in
            let rotation = ImageFreeRotation(radians: CGFloat(degrees) * .pi / 180)
            guard let turned = rotation.image(from: source) else { return nil }
            return (.free(rotation), scaledDown(turned, maxSide: 720))
        }
    }

    private static func render(_ turn: ScanTurn, from source: CGImage, maxSide: Int) -> CGImage? {
        let turned: CGImage?
        switch turn {
        case .quarter(let quarter):
            turned = quarter.image(from: source)
        case .free(let rotation):
            turned = rotation.image(from: source)
        }
        guard let turned else { return nil }
        return scaledDown(turned, maxSide: maxSide)
    }

    private static func pageReading(
        _ image: CGImage,
        level: VNRequestTextRecognitionLevel,
        turn: ScanTurn,
        original: CGImage,
        includeLiveText: Bool
    ) async -> PageReading {
        async let visionTask = visionRead(image, level: level)
        let live = includeLiveText ? ((try? await liveText(in: image)) ?? "") : ""
        let vision = await visionTask
        let text = richer(live, vision.text)
        let confidence = vision.lines.isEmpty ? (live.isEmpty ? 0 : 0.75) : meanConfidence(vision.lines)
        let lines = vision.lines.map { line in
            TextLineBox(
                text: line.text,
                bounds: turn.boundsInOriginal(
                    line.bounds,
                    width: CGFloat(original.width),
                    height: CGFloat(original.height)
                ),
                confidence: line.confidence
            )
        }
        return PageReading(text: text, confidence: confidence, lines: lines)
    }

    private static func visionRead(_ image: CGImage, level: VNRequestTextRecognitionLevel) async -> VisionRead {
        if level == .accurate {
            return (try? await recognizeWithTimeout(
                in: image,
                level: .accurate,
                recognitionLanguages: fallbackRecognitionLanguages
            )) ?? .empty
        }
        return await Task.detached(priority: .userInitiated) {
            (try? recognize(in: image, level: .fast, recognitionLanguages: fallbackRecognitionLanguages)) ?? .empty
        }.value
    }

    private static func scaledDown(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = Double(maxSide) / Double(longest)
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        return draw(image, width: width, height: height) ?? image
    }

    private static func richer(_ first: String, _ second: String) -> String {
        let left = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        let leftScore = SidewaysText.wordScore(left, confidence: 1)
        let rightScore = SidewaysText.wordScore(right, confidence: 1)
        if leftScore == rightScore {
            return left.count >= right.count ? left : right
        }
        return leftScore > rightScore ? left : right
    }

    private static func nonOverlapping(_ lines: [TextLineBox], avoiding existing: [TextLineBox]) -> [TextLineBox] {
        guard !existing.isEmpty else { return [] }
        return lines.filter { line in
            guard line.confidence >= sidewaysConfidence else { return false }
            return !existing.contains { overlapFraction($0.bounds, line.bounds) > 0.45 }
        }
    }

    private static func meanConfidence(_ lines: [TextLineBox]) -> Float {
        guard !lines.isEmpty else { return 0 }
        return lines.reduce(Float(0)) { $0 + $1.confidence } / Float(lines.count)
    }

    private static func overlapFraction(_ upright: CGRect, _ sideways: CGRect) -> CGFloat {
        let hit = upright.intersection(sideways)
        guard !hit.isNull, !hit.isEmpty else { return 0 }
        let area = sideways.width * sideways.height
        guard area > 0 else { return 0 }
        return (hit.width * hit.height) / area
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
