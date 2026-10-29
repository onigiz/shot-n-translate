import AppKit
import Foundation
import PDFKit
import ShotNTranslateCore

@main
struct ShotNTranslateChecks {
    static func main() async {
        do {
            try checkLocalization()
            try await checkCaptureFoundation()
            try checkImageRegion()
            try checkTranslationText()
            try await checkPreferences()
            try checkReleases()
            try await checkInstaller()
            try await checkPublicReleaseAccess()
            print("All checks passed")
        } catch {
            fputs("\(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct CheckError: Error, CustomStringConvertible {
    var description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw CheckError(description: message)
    }
}

private func checkLocalization() throws {
    let identicalOnPurpose: Set<L10nKey> = [.languageOptionTurkish, .languageOptionEnglish]
    for key in L10nKey.allCases {
        let turkish = L10n.string(key, language: .turkish)
        let english = L10n.string(key, language: .english)
        try expect(!turkish.isEmpty, "Missing Turkish string for \(key)")
        try expect(!english.isEmpty, "Missing English string for \(key)")
        if identicalOnPurpose.contains(key) {
            try expect(turkish == english, "\(key) should match in both languages")
        } else {
            try expect(turkish != english, "\(key) should differ between languages")
        }
    }
    try expect(L10n.string(.languageOptionTurkish, language: .english) == "Türkçe", "Turkish language label")
    try expect(L10n.string(.languageOptionEnglish, language: .turkish) == "English", "English language label")
    try expect(L10n.string(.patchNotesLanguageCaption, language: .turkish).contains("İngilizce"), "Patch note caption")
    for language in AppLanguage.allCases {
        try expect(!L10n.installedVersionLine("0.1.0 (1)", language: language).isEmpty, "Installed version line")
        try expect(L10n.menuUpdateAvailable(version: "0.2.0", language: language).contains("0.2.0"), "Update menu line")
    }
    try expect(
        L10n.confirmUpdateMessage(version: "0.2.0", language: .turkish)
            != L10n.confirmUpdateMessage(version: "0.2.0", language: .english),
        "Update confirmation should be localized"
    )
}

private func checkCaptureFoundation() async throws {
    let primaryMaxY: CGFloat = 900
    let top = CaptureCoordinateSpace.displayRect(
        fromAppKitRect: CGRect(x: 10, y: 800, width: 100, height: 50),
        primaryScreenMaxY: primaryMaxY
    )
    try expect(top == CGRect(x: 10, y: 50, width: 100, height: 50), "Top AppKit rect maps near the display top")
    let bottom = CaptureCoordinateSpace.displayRect(
        fromAppKitRect: CGRect(x: 10, y: 0, width: 100, height: 50),
        primaryScreenMaxY: primaryMaxY
    )
    try expect(bottom == CGRect(x: 10, y: 850, width: 100, height: 50), "Bottom AppKit rect maps near the display bottom")
    let above = CaptureCoordinateSpace.displayRect(
        fromAppKitRect: CGRect(x: 0, y: 900, width: 800, height: 100),
        primaryScreenMaxY: primaryMaxY
    )
    try expect(above.origin.y == -100, "A display above the primary screen has a negative display Y")
    let secondary = CGRect(x: 1920, y: 124, width: 1470, height: 956)
    let onSecondary = CaptureCoordinateSpace.localDisplayRect(
        appKitRect: CGRect(x: 2000, y: 500, width: 400, height: 200),
        screenFrame: secondary
    )
    try expect(
        onSecondary == CGRect(x: 80, y: 380, width: 400, height: 200),
        "A secondary-display selection is local to that display's top-left"
    )
    try expect(
        CaptureCoordinateSpace.screencaptureRectArgument(CGRect(x: 10.4, y: 20.6, width: 100.2, height: 50.8))
            == "10,21,100,51",
        "screencapture -R uses rounded Quartz x,y,w,h"
    )
    try expect(
        CaptureCoordinateSpace.screencaptureRectArgument(CGRect(x: 0, y: 0, width: 0.2, height: 0.2))
            == "0,0,1,1",
        "screencapture -R keeps at least a 1x1 region"
    )

    let english = LanguageDetector.detectCode(in: "Hello, the weather in the city is very nice and the sea was calm today.")
    let turkish = LanguageDetector.detectCode(in: "Merhaba, bugün İstanbul'da hava çok güzel ve deniz oldukça sakindi.")
    try expect(english == "en", "English detection")
    try expect(turkish == "tr", "Turkish detection")
    try expect(LanguageDetector.detectCode(in: "   ") == nil, "Blank text has no language")
    try expect(
        LanguageDetector.detectCode(in: "Bu metin Türkçe karakterler içerir: şğüöçı") == "tr",
        "Turkish diacritics identify Turkish"
    )
    try expect(
        LanguageDetector.detectCode(in: "HELLO WORLD FROM SCREEN") == "en",
        "Short Latin OCR text falls back to English"
    )
    try expect(
        LanguageDetector.detectCode(in: "??? ###", visionHints: ["de"]) == "de",
        "Vision language hints are used when text has no script signal"
    )
    try expect(
        !LanguageDetector.detect(in: "??? ###", visionHints: ["de"]).isConfident,
        "A vision hint alone is not passed to Translation"
    )
    let englishWithKana = "Hello, the weather in the city is very nice and the sea was calm today.\u{3042}"
    try expect(
        LanguageDetector.detectCode(in: englishWithKana) == "en",
        "One kana character does not make English text Japanese"
    )
    try expect(
        LanguageDetector.detect(in: englishWithKana).isConfident,
        "Mostly Latin text keeps a confident English source"
    )
    try expect(
        LanguageDetector.detectCode(in: "これはテストです。今日はいい天気。") == "ja",
        "Japanese text with kana is still Japanese"
    )
    try expect(
        LanguageDetector.detectCode(in: "你好世界") == "zh",
        "Han text without kana is Chinese"
    )
    try expect(LanguageDetector.detectCode(in: "\u{3042}") != "ja", "A single kana character is not Japanese")
    try expect(LanguageDetector.matches("en-US", target: .english), "Regional English matches the English target")
    try expect(!LanguageDetector.matches("tr", target: .english), "Turkish does not match the English target")

    try expect(ShortcutCatalog.items.first?.function == .translateSelection, "First shortcut translates a selection")
    try expect(
        Set(ShortcutCatalog.items.map(\.function)).count == ShortcutCatalog.items.count,
        "Shortcut functions are unique"
    )
    try expect(Set(ShortcutCatalog.items.map(\.key)).count == ShortcutCatalog.items.count, "Shortcut keys are unique")
    try expect(
        ShortcutCatalog.items.allSatisfy { $0.command && $0.shift && $0.key.count == 1 },
        "Shortcuts use Command-Shift and one key"
    )

    let image = try renderedTextImage("HELLO")
    let recognized = try await TextRecognizer.recognize(in: image)
    try expect(recognized.text.uppercased().contains("HELLO"), "Vision reads rendered text, got \(recognized.text)")

    let page = try renderedTextImage(
        "Install and open the latest Mac release",
        width: 1400,
        height: 1800,
        fontSize: 18,
        dark: true
    )
    let pageText = try await TextRecognizer.recognize(in: page).text.lowercased()
    try expect(pageText.contains("install"), "Small text in a tall dark capture is read, got \(pageText)")
    let stacked = try renderedStackedLines(
        ["Install and open the latest Mac release", "Make it your own in Settings"],
        width: 1600,
        height: 1800,
        fontSize: 18
    )
    let stackedText = try await TextRecognizer.recognize(in: stacked).text.lowercased()
    try expect(stackedText.contains("install"), "Top line of a tall capture is read, got \(stackedText)")
    try expect(stackedText.contains("settings"), "Bottom line of a tall capture is read, got \(stackedText)")
    try expect(TextRecognizer.contrast(page) > 0.2, "A text page has visible contrast")
    let pageBright = TextRecognizer.brightPixelFraction(page)
    try expect(TextRecognizer.shouldInvertForOCR(page), "A dark text page should be inverted for OCR")
    try expect(TextRecognizer.meanLuminance(page) < 0.45, "A dark text page has low mean luminance")
    if let inverted = TextRecognizer.invertedImage(page) {
        try expect(
            TextRecognizer.meanLuminance(inverted) > TextRecognizer.meanLuminance(page),
            "Inverting a dark page raises mean luminance"
        )
    } else {
        throw CheckError(description: "Dark page inversion should produce an image")
    }
    let blank = try renderedTextImage(" ", width: 200, height: 200, fontSize: 12, dark: true)
    try expect(TextRecognizer.contrast(blank) < 0.04, "A black capture has no contrast")
    try expect(TextRecognizer.brightPixelFraction(blank) < 0.004, "A black capture has no light pixels")
    try expect(pageBright > TextRecognizer.brightPixelFraction(blank), "A text page is brighter than a black capture")
    try expect(!TextRecognizer.shouldInvertForOCR(blank), "A black capture should not be inverted")
    try checkPreviewPDF(image: page)

    let softDark = try renderedTextImage(
        "Soft gray body text on a dark IDE background",
        width: 1600,
        height: 900,
        fontSize: 28,
        dark: true,
        foreground: NSColor(white: 0.72, alpha: 1)
    )
    let softText = try await TextRecognizer.recognize(in: softDark).text.lowercased()
    try expect(softText.contains("soft") || softText.contains("gray") || softText.contains("ide"),
               "Soft light text on a dark page is read, got \(softText)")
}

private func renderedTextImage(
    _ text: String,
    width: Int = 1200,
    height: Int = 240,
    fontSize: CGFloat = 96,
    dark: Bool = false,
    foreground: NSColor? = nil
) throws -> CGImage {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CheckError(description: "Could not create a text image")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    (dark ? NSColor.black : NSColor.white).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let textColor = foreground ?? (dark ? NSColor.white : NSColor.black)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
        .foregroundColor: textColor
    ]
    (text as NSString).draw(at: NSPoint(x: 40, y: CGFloat(height) - fontSize - 24), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = rep.cgImage else {
        throw CheckError(description: "Could not read the text image")
    }
    return image
}

private func renderedStackedLines(
    _ lines: [String],
    width: Int,
    height: Int,
    fontSize: CGFloat
) throws -> CGImage {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CheckError(description: "Could not create a stacked text image")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
        .foregroundColor: NSColor.white
    ]
    for (index, line) in lines.enumerated() {
        let y: CGFloat
        if index == 0 {
            y = CGFloat(height) - fontSize - 24
        } else if index == lines.count - 1 {
            y = 40
        } else {
            let span = CGFloat(height) - fontSize - 80
            y = 40 + span * CGFloat(index) / CGFloat(max(lines.count - 1, 1))
        }
        (line as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: attributes)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let image = rep.cgImage else {
        throw CheckError(description: "Could not read the stacked text image")
    }
    return image
}

private func checkPreviewPDF(image: CGImage) throws {
    let translated = CaptureTranslation(
        original: "Hello from the screen",
        sourceLanguageCode: "en",
        translatedText: "Ekrandan merhaba",
        note: nil
    )
    try expect(translated.textForPreview == "Ekrandan merhaba", "Preview shows the translation")
    let already = CaptureTranslation(
        original: "Bu metin zaten Turkce",
        sourceLanguageCode: "tr",
        translatedText: nil,
        note: .alreadyInTargetLanguage
    )
    try expect(already.textForPreview == "Bu metin zaten Turkce", "Text already in the target language is the preview")
    let unavailable = CaptureTranslation(
        original: "Hello",
        sourceLanguageCode: "en",
        translatedText: nil,
        note: .translationUnavailable
    )
    try expect(unavailable.textForPreview == nil, "A missing translation is not preview text")

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("snt-preview-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try TranslationPreviewPDF.write(image: image, translation: "Ekrandan merhaba", to: url)
    guard let document = PDFDocument(url: url) else {
        throw CheckError(description: "Saved preview is not a PDF")
    }
    try expect(document.pageCount >= 1, "Preview PDF has a page")
    let extracted = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    try expect(extracted.contains("Ekrandan merhaba"), "Preview PDF contains the translation, got \(extracted)")

    let long = (1...80).map { "Translated line \($0) stays under the screenshot." }.joined(separator: "\n")
    let longURL = FileManager.default.temporaryDirectory.appendingPathComponent("snt-preview-long-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: longURL) }
    try TranslationPreviewPDF.write(image: image, translation: long, to: longURL)
    guard let longDocument = PDFDocument(url: longURL) else {
        throw CheckError(description: "Long preview is not a PDF")
    }
    try expect(longDocument.pageCount > 1, "A long translation continues on later pages, pages \(longDocument.pageCount)")

    let styled = NSMutableAttributedString(string: "Kalın satır", attributes: [
        .font: NSFont.boldSystemFont(ofSize: 18),
        .foregroundColor: NSColor.white
    ])
    let styledURL = FileManager.default.temporaryDirectory.appendingPathComponent("snt-preview-styled-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: styledURL) }
    try TranslationPreviewPDF.write(image: image, document: styled, darkBackground: true, to: styledURL)
    guard let styledDocument = PDFDocument(url: styledURL) else {
        throw CheckError(description: "Styled preview is not a PDF")
    }
    let styledText = (0..<styledDocument.pageCount).compactMap { styledDocument.page(at: $0)?.string }.joined(separator: "\n")
    try expect(styledText.contains("Kalın satır"), "Styled PDF keeps the edited translation, got \(styledText)")
}

@MainActor
private func checkImageRegion() throws {
    let frame = ImageRegionGeometry.displayFrame(
        imageWidth: 400,
        imageHeight: 200,
        in: CGSize(width: 220, height: 140)
    )
    try expect(abs(frame.width - 220) < 0.1, "Image fits the view width")
    try expect(abs(frame.height - 110) < 0.1, "Image keeps its aspect in the view")
    let leftHalf = CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height)
    let pixels = ImageRegionGeometry.pixelRect(
        selection: leftHalf,
        displayFrame: frame,
        imageWidth: 400,
        imageHeight: 200
    )
    try expect(pixels == CGRect(x: 0, y: 0, width: 200, height: 200), "Left half maps to left image pixels")
    let roundTrip = ImageRegionGeometry.viewRect(
        pixelRect: pixels ?? .zero,
        displayFrame: frame,
        imageWidth: 400,
        imageHeight: 200
    )
    try expect(abs(roundTrip.minX - leftHalf.minX) < 1, "Pixel selection maps back onto the view")
    try expect(
        ImageRegionGeometry.pixelRect(
            selection: CGRect(x: frame.minX, y: frame.minY, width: 1.2, height: 1.2),
            displayFrame: frame,
            imageWidth: 400,
            imageHeight: 200
        ) == nil,
        "A tiny drag is not a translation region"
    )
    try expect(
        ImageRegionGeometry.fullRect(width: 400, height: 200) == CGRect(x: 0, y: 0, width: 400, height: 200),
        "Command-A uses the whole screenshot"
    )

    let source = quadrantImage(width: 40, height: 20)
    let topLeft = ImageRegionCrop.recognitionImage(
        from: source,
        pixelRect: CGRect(x: 0, y: 0, width: 20, height: 10)
    )
    let bottomRight = ImageRegionCrop.recognitionImage(
        from: source,
        pixelRect: CGRect(x: 20, y: 10, width: 20, height: 10)
    )
    try expect(source.width == 40 && source.height == 20, "Choosing a region does not crop the screenshot")
    try expect(topLeft.width == 20 && topLeft.height == 10, "Recognition uses only the selected pixels")
    try expect(TextRecognizer.meanLuminance(topLeft) > 0.8, "The top-left of the screenshot stays the top-left")
    try expect(TextRecognizer.meanLuminance(bottomRight) < 0.1, "The bottom-right of the screenshot stays dark")
    let whole = ImageRegionCrop.recognitionImage(
        from: source,
        pixelRect: ImageRegionGeometry.fullRect(width: source.width, height: source.height)
    )
    try expect(whole.width == source.width && whole.height == source.height, "The whole image is read unchanged")
}

private func quadrantImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
    return context.makeImage()!
}

@MainActor
private func checkTranslationText() throws {
    let wrapped = """
    The weather in the city
    was very nice today.
    """
    try expect(
        TranslationText.prepare(wrapped) == "The weather in the city was very nice today.",
        "A wrapped paragraph becomes one sentence"
    )
    let twoParagraphs = """
    First paragraph
    continues.

    Second paragraph
    continues.
    """
    try expect(
        TranslationText.prepare(twoParagraphs) == "First paragraph continues.\n\nSecond paragraph continues.",
        "A blank line keeps two paragraphs"
    )
    let list = """
    Read this introduction
    carefully.
    - First item
    - Second item
    """
    let preparedList = TranslationText.prepare(list)
    try expect(
        preparedList == "Read this introduction carefully.\n\n- First item\n\n- Second item",
        "A bullet list stays apart from the prose"
    )
    try expect(
        TranslationText.paragraphs(in: preparedList).count == 3,
        "Each bullet is its own translation paragraph"
    )
    try expect(
        TranslationText.prepare("The com-\nputer is ready.") == "The computer is ready.",
        "A hyphen at the end of a line joins the word"
    )
    let realParagraphs = """
    The weather in the city was very
    nice and people walked by the sea
    all afternoon.
    Next paragraph starts with a longer
    line about the harbor and the boats.
    """
    try expect(
        TranslationText.prepare(realParagraphs) == """
        The weather in the city was very nice and people walked by the sea all afternoon.

        Next paragraph starts with a longer line about the harbor and the boats.
        """,
        "A short sentence ending starts a new paragraph with a blank line"
    )
    let fullLine = """
    The weather in the city was very nice today.
    People walked by the sea all afternoon and
    the wind stayed calm until evening.
    """
    try expect(
        !TranslationText.prepare(fullLine).contains("\n\n"),
        "A full line that ends a sentence stays in the same paragraph"
    )
    try expect(
        TranslationText.prepare(
            "Languages|AppLanguage.defaultLanguage is the language used until a person chooses one in the menu."
        ) == """
        Languages

        AppLanguage.defaultLanguage is the language used until a person chooses one in the menu.
        """,
        "A heading glued to the body by a bar is split"
    )
    try expect(
        TranslationText.prepare("Languages\n———\nAppLanguage.defaultLanguage is the language used until a person chooses one.")
            == """
        Languages

        AppLanguage.defaultLanguage is the language used until a person chooses one.
        """,
        "A heading stays above its paragraph and a rule is dropped"
    )
    let laidOut = TextLayout.transcript(from: [
        TextLineBox(text: "Languages", bounds: CGRect(x: 0.05, y: 0.90, width: 0.16, height: 0.035)),
        TextLineBox(text: "———", bounds: CGRect(x: 0.05, y: 0.868, width: 0.8, height: 0.004)),
        TextLineBox(
            text: "AppLanguage.defaultLanguage is the language used until a person chooses one.",
            bounds: CGRect(x: 0.05, y: 0.80, width: 0.85, height: 0.02)
        ),
        TextLineBox(
            text: "Both English and Turkish strings live in L10n.",
            bounds: CGRect(x: 0.05, y: 0.70, width: 0.85, height: 0.02)
        ),
        TextLineBox(text: "Translation", bounds: CGRect(x: 0.05, y: 0.60, width: 0.2, height: 0.035))
    ])
    try expect(
        laidOut == """
        Languages

        AppLanguage.defaultLanguage is the language used until a person chooses one.

        Both English and Turkish strings live in L10n.

        Translation
        """,
        "A larger gap and a heading start a new paragraph"
    )
    try expect(
        TranslationText.isPreferred(
            "Languages\n\nThe menu stores the target language.",
            over: "Languages The menu stores the target language."
        ),
        "A transcript that kept the heading beats a flat copy"
    )
    try expect(
        TranslationText.prepare(TranslationText.prepare(twoParagraphs)) == TranslationText.prepare(twoParagraphs),
        "Preparing a transcript twice leaves it unchanged"
    )
    try expect(
        TranslationText.isPreferred(
            "The weather in the city was very nice today.",
            over: "The weather in the city\nwas very nice today."
        ),
        "The same words in a paragraph beat a line-broken copy"
    )
    try expect(
        TranslationText.isPreferred(
            "One\nTwo\nThree\nFour extra sentence is here today.",
            over: "One."
        ),
        "A much longer transcript still wins"
    )
}

@MainActor
private func checkPreferences() async throws {
    let languageDefaults = makeDefaults()
    let languageStore = LanguageStore(defaults: languageDefaults)
    try expect(AppLanguage.defaultLanguage == .turkish, "Default app language")
    try expect(languageStore.language == .turkish, "Unset app language")

    let storedLanguage = makeDefaults()
    storedLanguage.set(AppLanguage.english.rawValue, forKey: LanguageStore.storageKey)
    try expect(LanguageStore(defaults: storedLanguage).language == .english, "Stored app language")

    let unknownLanguage = makeDefaults()
    unknownLanguage.set("de", forKey: LanguageStore.storageKey)
    try expect(LanguageStore(defaults: unknownLanguage).language == .defaultLanguage, "Unknown app language")

    let persistedLanguage = makeDefaults()
    let editableLanguage = LanguageStore(defaults: persistedLanguage)
    editableLanguage.language = .english
    try expect(LanguageStore(defaults: persistedLanguage).language == .english, "Persisted app language")

    let targetDefaults = makeDefaults()
    let settings = TranslationSettings(defaults: targetDefaults)
    try expect(TranslationTarget.defaultTarget == .turkish, "Default translation target")
    try expect(settings.target == .turkish, "Unset translation target")
    settings.target = .english
    try expect(TranslationSettings(defaults: targetDefaults).target == .english, "Persisted translation target")
    try expect(TranslationScope.defaultScope == .immediate, "Default translation scope")
    try expect(settings.scope == .immediate, "Unset translation scope")
    settings.scope = .regionFirst
    try expect(TranslationSettings(defaults: targetDefaults).scope == .regionFirst, "Persisted translation scope")
    let unknownScope = makeDefaults()
    unknownScope.set("nope", forKey: TranslationSettings.scopeStorageKey)
    try expect(TranslationSettings(defaults: unknownScope).scope == .immediate, "Unknown translation scope")
}

private func checkReleases() throws {
    try expect(SemanticVersion(parsing: "v0.1.0") == SemanticVersion(major: 0, minor: 1, patch: 0), "v prefix")
    try expect(SemanticVersion(parsing: "1.2") == nil, "Reject short versions")
    try expect(SemanticVersion(parsing: "1.2.3-beta") == nil, "Reject pre-release tags")
    try expect(SemanticVersion(parsing: AppReleaseIdentity.marketingVersion) != nil, "Marketing version")

    let older = SemanticVersion(major: 0, minor: 1, patch: 9)
    let current = SemanticVersion(major: 0, minor: 2, patch: 0)
    let newer = SemanticVersion(major: 0, minor: 2, patch: 1)
    try expect(versionRelation(of: newer, to: current) == .newer, "Newer relation")
    try expect(versionRelation(of: current, to: current) == .current, "Current relation")
    try expect(versionRelation(of: older, to: current) == .older, "Older relation")

    let releases = try GitHubReleasesFeed.parse(Data(sampleFeed.utf8))
    try expect(releases.map(\.version.description) == ["0.3.0", "0.2.0"], "Release order")
    try expect(releases[1].notes == "Add English as a translation target.", "English notes stay unchanged")
    try expect(
        releases[1].downloadURL?.absoluteString == "https://api.github.com/repos/onigiz/shot-n-translate/releases/assets/22",
        "Preferred zip asset"
    )

    let official = URL(string: "https://github.com/onigiz/shot-n-translate/releases/download/v0.2.0/ShotNTranslate.zip")!
    let apiAsset = URL(string: "https://api.github.com/repos/onigiz/shot-n-translate/releases/assets/22")!
    let otherRepo = URL(string: "https://github.com/example/shot-n-translate/releases/download/v0.2.0/ShotNTranslate.zip")!
    try expect(ReleaseAssetPolicy.isOfficialDownloadURL(official), "Official asset URL")
    try expect(ReleaseAssetPolicy.isOfficialDownloadURL(apiAsset), "Official API asset URL")
    try expect(!ReleaseAssetPolicy.isOfficialDownloadURL(otherRepo), "Foreign asset URL")
    try expect(AppRelauncher.script.contains("ditto") && AppRelauncher.script.contains("open"), "Relaunch script")
}

@MainActor
private func checkInstaller() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("snt-checks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try makeApp(named: "Helper.app", in: root)
    let preferred = try makeApp(named: "\(AppReleaseIdentity.applicationName).app", in: root)
    let found = try AppArchive.locateApplication(in: root)
    try expect(found.standardizedFileURL == preferred.standardizedFileURL, "Preferred app in archive")

    let empty = root.appendingPathComponent("empty", isDirectory: true)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    do {
        _ = try AppArchive.locateApplication(in: empty)
        throw CheckError(description: "Empty archive should fail")
    } catch let failure as UpdateFailure {
        try expect(failure == .archiveDoesNotContainApp, "Empty archive error")
    }

    let packaged = try makeApp(named: "\(AppReleaseIdentity.applicationName).app", in: root.appendingPathComponent("package", isDirectory: true))
    let zip = root.appendingPathComponent("ShotNTranslate.zip")
    try zipApp(packaged, to: zip)
    let destination = try makeApp(named: "Installed.app", in: root.appendingPathComponent("dest", isDirectory: true))
    let recorder = RelaunchRecorder()
    let installer = AppUpdateInstaller(
        bundleURL: { destination },
        download: { _ in zip },
        relaunch: { staged, dest in
            recorder.staged = staged
            recorder.destination = dest
        }
    )
    let center = UpdateCenter(
        feed: StaticFeed(releases: []),
        installer: installer,
        current: AppVersion(marketing: SemanticVersion(major: 0, minor: 1, patch: 0), build: 1)
    )
    let quitter = QuitRecorder()
    center.quit = { quitter.count += 1 }
    await center.install(AppRelease(
        version: SemanticVersion(major: 0, minor: 2, patch: 0),
        publishedAt: nil,
        notes: "English notes stay English.",
        downloadURL: URL(string: "https://github.com/onigiz/shot-n-translate/releases/download/v0.2.0/ShotNTranslate.zip"),
        releaseURL: nil
    ))
    try expect(quitter.count == 1, "Install quits the app")
    try expect(center.status == .installing, "Install status")
    try expect(recorder.destination == destination, "Install destination")
    if let staged = recorder.staged {
        try? FileManager.default.removeItem(at: staged)
    }

    let blocked = UpdateCenter(
        feed: StaticFeed(releases: []),
        installer: AppUpdateInstaller(
            bundleURL: { URL(fileURLWithPath: "/tmp/Shot n Translate.app") },
            download: { _ in throw UpdateFailure.downloadFailed },
            relaunch: { _, _ in }
        ),
        current: AppReleaseIdentity.fallback
    )
    let blockedQuit = QuitRecorder()
    blocked.quit = { blockedQuit.count += 1 }
    await blocked.install(AppRelease(
        version: SemanticVersion(major: 9, minor: 0, patch: 0),
        publishedAt: nil,
        notes: "",
        downloadURL: URL(string: "https://example.com/ShotNTranslate.zip"),
        releaseURL: nil
    ))
    try expect(blockedQuit.count == 0, "Untrusted download does not quit")
    try expect(blocked.status == .failed(.untrustedDownloadURL), "Untrusted download status")

    let history = UpdateCenter(
        feed: StaticFeed(releases: [
            AppRelease(version: SemanticVersion(major: 0, minor: 1, patch: 0), publishedAt: nil, notes: "Older.", downloadURL: nil, releaseURL: nil),
            AppRelease(version: SemanticVersion(major: 0, minor: 3, patch: 0), publishedAt: nil, notes: "Newer.", downloadURL: nil, releaseURL: nil),
            AppRelease(version: SemanticVersion(major: 0, minor: 2, patch: 0), publishedAt: nil, notes: "Current.", downloadURL: nil, releaseURL: nil)
        ]),
        installer: AppUpdateInstaller(bundleURL: { nil }, download: { _ in throw UpdateFailure.downloadFailed }, relaunch: { _, _ in }),
        current: AppVersion(marketing: SemanticVersion(major: 0, minor: 2, patch: 0), build: 1)
    )
    await history.checkForUpdates()
    try expect(history.releases.map(\.version.description) == ["0.3.0", "0.2.0", "0.1.0"], "History order")
    try expect(history.relation(of: history.releases[0]) == .newer, "Newest relation")
    try expect(history.relation(of: history.releases[2]) == .older, "Oldest relation")
    try expect(history.newestUpdate?.notes == "Newer.", "Newest notes")
}

private func checkPublicReleaseAccess() async throws {
    let releases = try await GitHubReleasesFeed().fetch()
    guard let url = releases.compactMap(\.downloadURL).first else { return }
    let file = try await ReleaseDownloader.download(url)
    defer { try? FileManager.default.removeItem(at: file) }
    let header = try Data(contentsOf: file, options: [.mappedIfSafe]).prefix(2)
    try expect(Array(header) == [0x50, 0x4b], "Release package is a zip")
}

private struct StaticFeed: ReleaseFetching {
    var releases: [AppRelease]
    func fetch() async throws -> [AppRelease] { releases }
}

private final class RelaunchRecorder: @unchecked Sendable {
    var staged: URL?
    var destination: URL?
}

private final class QuitRecorder: @unchecked Sendable {
    var count = 0
}

private func makeDefaults() -> UserDefaults {
    let name = "ShotNTranslateChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func makeApp(named name: String, in root: URL) throws -> URL {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let app = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
    return app
}

private func zipApp(_ app: URL, to zip: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
    try process.run()
    process.waitUntilExit()
    try expect(process.terminationStatus == 0, "ditto zip")
}

private let sampleFeed = """
[
  {
    "tag_name": "v0.2.0",
    "body": "Add English as a translation target.",
    "draft": false,
    "prerelease": false,
    "published_at": "2026-09-01T12:00:00Z",
    "html_url": "https://github.com/onigiz/shot-n-translate/releases/tag/v0.2.0",
    "assets": [
      {
        "name": "Other.zip",
        "id": 11,
        "browser_download_url": "https://github.com/onigiz/shot-n-translate/releases/download/v0.2.0/Other.zip"
      },
      {
        "name": "ShotNTranslate.zip",
        "id": 22,
        "browser_download_url": "https://github.com/onigiz/shot-n-translate/releases/download/v0.2.0/ShotNTranslate.zip"
      }
    ]
  },
  {
    "tag_name": "v0.3.0",
    "body": "Show update history.",
    "draft": false,
    "prerelease": false,
    "published_at": "2026-10-01T12:00:00Z",
    "html_url": "https://github.com/onigiz/shot-n-translate/releases/tag/v0.3.0",
    "assets": [
      {
        "name": "ShotNTranslate.zip",
        "id": 33,
        "browser_download_url": "https://github.com/onigiz/shot-n-translate/releases/download/v0.3.0/ShotNTranslate.zip"
      }
    ]
  },
  {
    "tag_name": "v0.4.0",
    "body": "Beta notes",
    "draft": false,
    "prerelease": true,
    "published_at": "2026-10-02T12:00:00Z",
    "html_url": "https://github.com/onigiz/shot-n-translate/releases/tag/v0.4.0",
    "assets": []
  },
  {
    "tag_name": "v0.9.0",
    "body": "Draft notes",
    "draft": true,
    "prerelease": false,
    "published_at": "2026-10-03T12:00:00Z",
    "html_url": "https://github.com/onigiz/shot-n-translate/releases/tag/v0.9.0",
    "assets": []
  }
]
"""
