import AppKit
import ShotNTranslateCore
import SwiftUI
@preconcurrency import Translation

@MainActor
enum TranslationResultWindow {
    private static var window: NSWindow?
    private static let closeDelegate = PreviewWindowDelegate()

    static func hideWithoutReleasing() {
        window?.orderOut(nil)
    }

    static func show(translator: ScreenshotTranslator, languageStore: LanguageStore) {
        if window == nil {
            let controller = NSHostingController(rootView: TranslationResultView()
                .environment(translator)
                .environment(languageStore))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.title = L10n.string(.translationResultTitle, language: languageStore.language)
            window.contentMinSize = NSSize(width: 420, height: 360)
            window.setContentSize(NSSize(width: 640, height: 720))
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.sharingType = .none
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            closeDelegate.onClose = { [weak translator] in
                translator?.releasePreview()
            }
            window.delegate = closeDelegate
            window.center()
            self.window = window
        }
        window?.alphaValue = 1
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private final class PreviewWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

struct TranslationResultView: View {
    @Environment(ScreenshotTranslator.self) private var translator
    @Environment(LanguageStore.self) private var languageStore

    var body: some View {
        let language = languageStore.language
        Group {
            switch translator.presentation {
            case .idle, .working:
                previewStack {
                    ProgressView(L10n.string(.readingSelection, language: language))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .failure(let key):
                ScrollView {
                    VStack(spacing: 16) {
                        if let preview = translator.capturePreview {
                            Image(nsImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            chooseRegionButton(language: language)
                        }
                        if key == .screenRecordingDenied {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text(L10n.string(.screenRecordingDeniedTitle, language: language))
                                .font(.title2.weight(.semibold))
                                .multilineTextAlignment(.center)
                            Text(L10n.string(.screenRecordingDenied, language: language))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(spacing: 10) {
                                Button(L10n.string(.resetScreenRecordingPermission, language: language)) {
                                    ScreenRecordingAccess.resetGrant()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                Button(L10n.string(.relaunchApp, language: language)) {
                                    ScreenRecordingAccess.relaunch()
                                }
                                .controlSize(.large)
                                Button(L10n.string(.openScreenRecordingSettings, language: language)) {
                                    ScreenRecordingAccess.openSettings()
                                }
                            }
                            .padding(.top, 4)
                        } else {
                            ContentUnavailableView(
                                L10n.string(key, language: language),
                                systemImage: "exclamationmark.triangle"
                            )
                            .frame(maxWidth: .infinity, minHeight: 160)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            case .result(let result):
                resultBody(result, language: language)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
        .background(WindowTitleSetter(title: L10n.string(.translationResultTitle, language: language)))
        .translationTask(translator.translationConfiguration) { session in
            let text = translator.textWaitingForTranslation()
            guard let text else { return }
            InstalledTranslation.track(session)
            defer { InstalledTranslation.release(session) }
            let generation = translator.currentTranslationID
            let paragraphs = TranslationText.paragraphs(in: TranslationText.prepare(text))
                .map { LanguageDetector.textForTranslation($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !paragraphs.isEmpty else {
                translator.finishTranslation(
                    of: text,
                    generation: generation,
                    translated: nil,
                    detectedSourceCode: nil
                )
                return
            }
            do {
                let outcome = try await translationOutcome(session: session, paragraphs: paragraphs)
                translator.finishTranslation(
                    of: text,
                    generation: generation,
                    translated: outcome.text.isEmpty ? nil : outcome.text,
                    detectedSourceCode: outcome.sourceCode
                )
            } catch {
                translator.finishTranslation(
                    of: text,
                    generation: generation,
                    translated: nil,
                    detectedSourceCode: nil
                )
            }
        }
    }

    private func resultBody(_ result: CaptureTranslation, language: AppLanguage) -> some View {
        VStack(spacing: 12) {
            if let preview = translator.capturePreview {
                RotatablePreview(
                    image: preview,
                    clockwiseDegrees: translator.previewTurn.clockwiseDegrees,
                    tool: translator.previewTool,
                    markColor: Color(
                        red: translator.shapeRed,
                        green: translator.shapeGreen,
                        blue: translator.shapeBlue
                    ),
                    outlineWidth: outlineWidth(for: preview),
                    help: L10n.string(.rotateImageHandle, language: language),
                    onDegrees: { translator.setPreviewClockwiseDegrees($0) },
                    onShape: { bounds in
                        let kind: PreviewMarkKind = translator.previewTool == .circle ? .circle : .square
                        translator.addPreviewMark(visibleBounds: bounds, kind: kind)
                    },
                    onCrop: { translator.cropPreview(toVisible: $0) }
                )
                previewMarkupToolbar(language: language)
            }
            chooseRegionButton(language: language)
            sourceMenu(result: result, language: language)
            if translator.isTranslating {
                ProgressView(L10n.string(.translating, language: language))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if translator.draft.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let note = result.note {
                Text(L10n.string(noteKey(note), language: language))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                editor(language: language)
            }
            Divider()
            HStack(spacing: 12) {
                if let notice = translator.saveNotice {
                    Text(L10n.string(notice, language: language))
                        .foregroundStyle(
                            notice == .pdfSaved || notice == .cardSaved
                                ? AnyShapeStyle(.secondary)
                                : AnyShapeStyle(.red)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let title = translator.openCardTitle {
                    Text(title)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                Button(L10n.string(.savePDF, language: language)) {
                    translator.savePDF()
                }
                .disabled(!translator.canSaveFormattedPDF)
                Button(L10n.string(.saveCard, language: language)) {
                    translator.saveCard()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!translator.canSaveCard)
            }
        }
    }

    private func editor(language: AppLanguage) -> some View {
        VStack(spacing: 8) {
            editorToolbar(language: language)
            TranslationTextEditor(
                text: translator.draft,
                reloadToken: translator.draftToken,
                isDark: translator.editorIsDark,
                controller: translator.editing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.35))
            )
        }
    }

    private func editorToolbar(language: AppLanguage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                formatButton("bold", help: .bold, language: language) {
                    translator.editing.toggleTrait(.boldFontMask)
                }
                formatButton("italic", help: .italic, language: language) {
                    translator.editing.toggleTrait(.italicFontMask)
                }
                formatButton("underline", help: .underline, language: language) {
                    translator.editing.toggleUnderline()
                }
                Divider().frame(height: 16)
                formatButton("text.alignleft", help: .alignLeading, language: language) {
                    translator.editing.align(.left)
                }
                formatButton("text.aligncenter", help: .alignCenter, language: language) {
                    translator.editing.align(.center)
                }
                formatButton("text.alignright", help: .alignTrailing, language: language) {
                    translator.editing.align(.right)
                }
                Divider().frame(height: 16)
                formatButton("textformat.size.smaller", help: .smallerText, language: language) {
                    translator.editing.changeSize(by: -1)
                }
                formatButton("textformat.size.larger", help: .largerText, language: language) {
                    translator.editing.changeSize(by: 1)
                }
                Menu {
                    ForEach(EditorColorChoices.all) { choice in
                        Button(L10n.string(choice.key, language: language)) {
                            translator.editing.apply(color: choice.color)
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.string(.textColor, language: language))
                Divider().frame(height: 16)
                Picker(L10n.string(.editorLight, language: language), selection: Binding(
                    get: { translator.editorIsDark },
                    set: { translator.setEditorSurface(isDark: $0) }
                )) {
                    Text(L10n.string(.editorLight, language: language)).tag(false)
                    Text(L10n.string(.editorDark, language: language)).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .labelsHidden()
            }
        }
    }

    private func formatButton(
        _ symbol: String,
        help: L10nKey,
        language: AppLanguage,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(L10n.string(help, language: language))
    }

    private func previewStack<Below: View>(
        @ViewBuilder below: () -> Below
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let preview = translator.capturePreview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                below()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func outlineWidth(for preview: NSImage) -> CGFloat {
        let shorter = min(preview.size.width, preview.size.height)
        return CGFloat(PreviewMarkup.strokeWidth(
            thickness: translator.shapeThickness,
            shorterSide: Double(shorter)
        ))
    }

    private func previewMarkupToolbar(language: AppLanguage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                markupToolButton("crop", tool: .crop, help: .cropImage, language: language)
                markupToolButton("square", tool: .square, help: .drawSquare, language: language)
                markupToolButton("circle", tool: .circle, help: .drawCircle, language: language)
                Divider().frame(height: 16)
                Menu {
                    ForEach(EditorColorChoices.all) { choice in
                        Button(L10n.string(choice.key, language: language)) {
                            let rgb = choice.color.usingColorSpace(.sRGB) ?? choice.color
                            translator.setShapeColor(
                                red: rgb.redComponent,
                                green: rgb.greenComponent,
                                blue: rgb.blueComponent
                            )
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(Color(
                            red: translator.shapeRed,
                            green: translator.shapeGreen,
                            blue: translator.shapeBlue
                        ))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.string(.shapeColor, language: language))
                Image(systemName: "lineweight")
                    .foregroundStyle(.secondary)
                    .help(L10n.string(.shapeThickness, language: language))
                Slider(
                    value: Binding(
                        get: { translator.shapeThickness },
                        set: { translator.setShapeThickness($0) }
                    ),
                    in: 1...12,
                    step: 1
                )
                .frame(width: 90)
                .help(L10n.string(.shapeThickness, language: language))
                if !translator.previewMarkup.marks.isEmpty {
                    Button {
                        translator.undoPreviewMark()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string(.undoMark, language: language))
                }
                if translator.previewMarkup.isCropped {
                    Button {
                        translator.resetPreviewCrop()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string(.resetCrop, language: language))
                }
            }
        }
    }

    private func markupToolButton(
        _ symbol: String,
        tool: PreviewCanvasTool,
        help: L10nKey,
        language: AppLanguage
    ) -> some View {
        Button {
            translator.selectPreviewTool(tool)
        } label: {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
                .padding(4)
                .background(
                    translator.previewTool == tool
                        ? Color.accentColor.opacity(0.22)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.borderless)
        .help(L10n.string(help, language: language))
    }

    private func chooseRegionButton(language: AppLanguage) -> some View {
        Button(L10n.string(.selectTranslationArea, language: language)) {
            Task { await translator.retranslateSelectedRegion() }
        }
        .disabled(translator.isBusy || translator.isTranslating || translator.capturePreview == nil)
    }

    private func sourceMenu(result: CaptureTranslation, language: AppLanguage) -> some View {
        let selected = result.sourceLanguageCode.map(LanguageDetector.baseCode)
        return HStack(spacing: 8) {
            Text(L10n.string(.sourceLanguage, language: language))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(translator.sourceChoices(selected: selected), id: \.self) { code in
                    Button {
                        translator.useSource(code)
                    } label: {
                        if code == selected {
                            Label(languageName(code, ui: language), systemImage: "checkmark")
                        } else {
                            Text(languageName(code, ui: language))
                        }
                    }
                }
            } label: {
                Text(selected.map { languageName($0, ui: language) } ?? L10n.string(.sourceDetectedAutomatically, language: language))
            }
            .fixedSize()
            Spacer()
        }
    }

    private func languageName(_ code: String, ui: AppLanguage) -> String {
        let locale = Locale(identifier: ui.rawValue)
        return locale.localizedString(forLanguageCode: code)
            ?? locale.localizedString(forIdentifier: code)
            ?? code
    }

    private func noteKey(_ note: CaptureTranslation.Note) -> L10nKey {
        switch note {
        case .alreadyInTargetLanguage: .alreadyInTargetLanguage
        case .languageNotDetected: .languageNotDetected
        case .translationUnavailable: .translationUnavailable
        }
    }

}

private struct RotatablePreview: View {
    var image: NSImage
    var clockwiseDegrees: Double
    var tool: PreviewCanvasTool
    var markColor: Color
    var outlineWidth: CGFloat
    var help: String
    var onDegrees: (Double) -> Void
    var onShape: (CGRect) -> Void
    var onCrop: (CGRect) -> Void

    @State private var dragStartDegrees: Double?
    @State private var dragGrabDegrees: Double?
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    private let pad: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let available = CGSize(
                width: max(geo.size.width - pad * 2, 1),
                height: max(geo.size.height - pad * 2, 1)
            )
            let fitted = fittedImageSize(in: available)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let stemEnd = shifted(
                center,
                by: PreviewRotationDrag.handleOffset(
                    imageHeight: fitted.height,
                    gap: 18,
                    clockwiseDegrees: clockwiseDegrees
                )
            )
            let edge = shifted(
                center,
                by: PreviewRotationDrag.handleOffset(
                    imageHeight: fitted.height,
                    gap: 2,
                    clockwiseDegrees: clockwiseDegrees
                )
            )
            ZStack {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                    if let draft = draftBounds {
                        draftOverlay(draft, size: fitted)
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .rotationEffect(.degrees(clockwiseDegrees))
                .position(center)
                Path { path in
                    path.move(to: edge)
                    path.addLine(to: stemEnd)
                }
                .stroke(Color.secondary, lineWidth: 1.5)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.secondary, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle().scale(1.6))
                    .position(stemEnd)
                    .highPriorityGesture(drag(center: center))
                    .help(help)
                    .accessibilityLabel(help)
                if dragStartDegrees != nil {
                    Text(degreeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(x: center.x, y: geo.size.height - 10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: "rotatablePreview")
            .gesture(drawGesture(center: center, imageSize: fitted))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
    }

    private var draftBounds: CGRect? {
        guard tool != .rotate, let dragStart, let dragCurrent else { return nil }
        let bounds = tool == .crop
            ? PreviewMarkupGeometry.rect(from: dragStart, to: dragCurrent)
            : PreviewMarkupGeometry.shapeBounds(from: dragStart, to: dragCurrent)
        guard bounds.width >= 0.01, bounds.height >= 0.01 else { return nil }
        return bounds
    }

    @ViewBuilder
    private func draftOverlay(_ bounds: CGRect, size: CGSize) -> some View {
        let rect = CGRect(
            x: bounds.minX * size.width,
            y: bounds.minY * size.height,
            width: bounds.width * size.width,
            height: bounds.height * size.height
        )
        if tool == .crop {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1)
                .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                .position(x: rect.midX, y: rect.midY)
        } else if tool == .circle {
            Ellipse()
                .stroke(markColor, lineWidth: outlineWidth)
                .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                .position(x: rect.midX, y: rect.midY)
        } else {
            Rectangle()
                .stroke(markColor, lineWidth: outlineWidth)
                .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private func drawGesture(center: CGPoint, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("rotatablePreview"))
            .onChanged { value in
                guard tool != .rotate else { return }
                let start = PreviewMarkupGeometry.visiblePoint(
                    value.startLocation,
                    center: center,
                    imageSize: imageSize,
                    clockwiseDegrees: clockwiseDegrees
                )
                let current = PreviewMarkupGeometry.visiblePoint(
                    value.location,
                    center: center,
                    imageSize: imageSize,
                    clockwiseDegrees: clockwiseDegrees
                )
                dragStart = clamped(start)
                dragCurrent = clamped(current)
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragCurrent = nil
                }
                guard tool != .rotate else { return }
                let start = clamped(PreviewMarkupGeometry.visiblePoint(
                    value.startLocation,
                    center: center,
                    imageSize: imageSize,
                    clockwiseDegrees: clockwiseDegrees
                ))
                let end = clamped(PreviewMarkupGeometry.visiblePoint(
                    value.location,
                    center: center,
                    imageSize: imageSize,
                    clockwiseDegrees: clockwiseDegrees
                ))
                let bounds = tool == .crop
                    ? PreviewMarkupGeometry.rect(from: start, to: end)
                    : PreviewMarkupGeometry.shapeBounds(from: start, to: end)
                guard bounds.width >= 0.02, bounds.height >= 0.02 else { return }
                if tool == .crop {
                    onCrop(bounds)
                } else {
                    onShape(bounds)
                }
            }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    private func drag(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("rotatablePreview"))
            .onChanged { value in
                guard let pointer = PreviewRotationDrag.clockwiseDegrees(from: center, to: value.location) else {
                    return
                }
                if dragStartDegrees == nil || dragGrabDegrees == nil {
                    dragStartDegrees = clockwiseDegrees
                    dragGrabDegrees = pointer
                }
                guard let dragStartDegrees, let dragGrabDegrees else { return }
                onDegrees(PreviewRotationDrag.imageDegrees(
                    startDegrees: dragStartDegrees,
                    grabDegrees: dragGrabDegrees,
                    pointerDegrees: pointer
                ))
            }
            .onEnded { _ in
                dragStartDegrees = nil
                dragGrabDegrees = nil
            }
    }

    private func fittedImageSize(in available: CGSize) -> CGSize {
        let source = image.size
        guard source.width > 0, source.height > 0 else { return CGSize(width: 1, height: 1) }
        let radians = clockwiseDegrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        let rotatedWidth = source.width * cosine + source.height * sine
        let rotatedHeight = source.width * sine + source.height * cosine
        let scale = min(available.width / rotatedWidth, available.height / rotatedHeight)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private var degreeLabel: String {
        let shown = Int(clockwiseDegrees.rounded())
        if shown > 0 { return "+\(shown)°" }
        return "\(shown)°"
    }

    private func shifted(_ point: CGPoint, by offset: CGPoint) -> CGPoint {
        CGPoint(x: point.x + offset.x, y: point.y + offset.y)
    }
}

private struct TranslationOutcome: Sendable {
    var text: String
    var sourceCode: String?
}

private enum TranslationWait: Error {
    case timedOut
}

/// Apple Translation can wait forever on a language download that a menu-bar app never shows.
/// Stop that wait so the preview does not stay on Translating.
private func translationOutcome(
    session: TranslationSession,
    paragraphs: [String]
) async throws -> TranslationOutcome {
    try await withThrowingTaskGroup(of: TranslationOutcome.self) { group in
        group.addTask {
            try await session.prepareTranslation()
            var pieces: [String] = []
            var sourceCode: String?
            for paragraph in paragraphs {
                let response = try await session.translate(paragraph)
                if sourceCode == nil {
                    sourceCode = response.sourceLanguage.languageCode?.identifier
                        ?? response.sourceLanguage.maximalIdentifier
                }
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !translated.isEmpty {
                    pieces.append(translated)
                }
            }
            return TranslationOutcome(text: pieces.joined(separator: "\n\n"), sourceCode: sourceCode)
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 20_000_000_000)
            throw TranslationWait.timedOut
        }
        let outcome = try await group.next()!
        group.cancelAll()
        return outcome
    }
}
