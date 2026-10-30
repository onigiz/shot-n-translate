import AppKit
import Carbon
import ShotNTranslateCore

/// Lets the user drag a rectangle on the captured screenshot.
/// Command-A treats the whole image as the selection and continues.
/// The returned rectangle is in top-left image pixels. The screenshot is not cropped.
@MainActor
final class ImageRegionPicker {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var keyMonitor: Any?
    private var didFinish = false
    private let image: CGImage

    init(image: CGImage) {
        self.image = image
    }

    func select(instruction: String, confirmTitle: String, cancelTitle: String, windowTitle: String) async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(
                instruction: instruction,
                confirmTitle: confirmTitle,
                cancelTitle: cancelTitle,
                windowTitle: windowTitle
            )
        }
    }

    private func present(
        instruction: String,
        confirmTitle: String,
        cancelTitle: String,
        windowTitle: String
    ) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxCanvas = CGSize(width: screen.width * 0.72, height: screen.height * 0.62)
        let imageW = CGFloat(max(image.width, 1))
        let imageH = CGFloat(max(image.height, 1))
        let scale = min(maxCanvas.width / imageW, maxCanvas.height / imageH, 1)
        let canvas = CGSize(
            width: max(imageW * scale, 360),
            height: max(imageH * scale, 200)
        )
        let chrome: CGFloat = 108
        let content = NSSize(width: canvas.width + 32, height: canvas.height + chrome)

        let panel = ImageRegionPanel(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = windowTitle
        panel.level = .floating
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let root = PickerRootView(frame: NSRect(origin: .zero, size: content))
        root.picker = self
        root.canvas.image = image
        root.instruction.stringValue = instruction
        root.translateButton.title = confirmTitle
        root.translateButton.target = root
        root.translateButton.action = #selector(PickerRootView.confirm)
        root.cancelButton.title = cancelTitle
        root.cancelButton.target = root
        root.cancelButton.action = #selector(PickerRootView.cancelClick)
        panel.contentView = root
        panel.setContentSize(content)
        panel.center()
        panel.delegate = root
        window = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(root.canvas)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                MainActor.assumeIsolated { self.finish(nil) }
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let selectAll = event.keyCode == UInt16(kVK_ANSI_A)
                && flags.contains(.command)
                && !flags.contains(.shift)
                && !flags.contains(.option)
                && !flags.contains(.control)
            if selectAll {
                MainActor.assumeIsolated { self.confirmFullImage() }
                return nil
            }
            return event
        }
    }

    func updateSelection(_ pixelRect: CGRect?) {
        guard let root = window?.contentView as? PickerRootView else { return }
        root.translateButton.isEnabled = pixelRect != nil
    }

    fileprivate func confirmFullImage() {
        complete(ImageRegionGeometry.fullRect(width: image.width, height: image.height))
    }

    fileprivate func finish(_ rect: CGRect?) {
        complete(rect)
    }

    private func complete(_ rect: CGRect?) {
        guard !didFinish, let continuation else { return }
        didFinish = true
        self.continuation = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.delegate = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        continuation.resume(returning: rect)
    }
}

private final class PickerRootView: NSView, NSWindowDelegate {
    weak var picker: ImageRegionPicker?
    let canvas = RegionCanvasView()
    let instruction = NSTextField(wrappingLabelWithString: "")
    let translateButton = NSButton(title: "", target: nil, action: nil)
    let cancelButton = NSButton(title: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        instruction.maximumNumberOfLines = 2
        instruction.textColor = .secondaryLabelColor
        translateButton.bezelStyle = .rounded
        translateButton.keyEquivalent = "\r"
        translateButton.isEnabled = false
        cancelButton.bezelStyle = .rounded
        addSubview(canvas)
        addSubview(instruction)
        addSubview(translateButton)
        addSubview(cancelButton)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let padding: CGFloat = 16
        let buttonHeight: CGFloat = 28
        cancelButton.sizeToFit()
        translateButton.sizeToFit()
        let cancelWidth = max(cancelButton.frame.width + 16, 96)
        let translateWidth = max(translateButton.frame.width + 20, 180)
        cancelButton.frame = NSRect(
            x: bounds.width - padding - cancelWidth,
            y: padding,
            width: cancelWidth,
            height: buttonHeight
        )
        translateButton.frame = NSRect(
            x: cancelButton.frame.minX - 8 - translateWidth,
            y: padding,
            width: translateWidth,
            height: buttonHeight
        )
        instruction.frame = NSRect(x: padding, y: padding + buttonHeight + 8, width: bounds.width - padding * 2, height: 36)
        let top = instruction.frame.maxY + 12
        canvas.frame = NSRect(x: padding, y: top, width: bounds.width - padding * 2, height: max(bounds.height - top - padding, 1))
    }

    func windowWillClose(_ notification: Notification) {
        picker?.finish(nil)
    }

    @objc func confirm() {
        guard let rect = canvas.pixelSelection else { return }
        picker?.finish(rect)
    }

    @objc func cancelClick() {
        picker?.finish(nil)
    }
}

private final class RegionCanvasView: NSView {
    var image: CGImage?
    var pixelSelection: CGRect?
    private var anchor: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        pixelSelection = nil
        picker?.updateSelection(nil)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        apply(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        apply(to: convert(event.locationInWindow, from: nil))
        anchor = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let image else { return }
        let frame = ImageRegionGeometry.displayFrame(
            imageWidth: image.width,
            imageHeight: image.height,
            in: bounds.size
        )
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            .draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
        guard let pixelSelection else { return }
        let selection = ImageRegionGeometry.viewRect(
            pixelRect: pixelSelection,
            displayFrame: frame,
            imageWidth: image.width,
            imageHeight: image.height
        )
        let shade = NSBezierPath(rect: frame)
        shade.append(NSBezierPath(rect: selection))
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        shade.fill()
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        border.stroke()
    }

    private var picker: ImageRegionPicker? {
        (superview as? PickerRootView)?.picker
    }

    private func apply(to point: CGPoint) {
        guard let image, let anchor else { return }
        let selection = CGRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(anchor.x - point.x),
            height: abs(anchor.y - point.y)
        )
        let frame = ImageRegionGeometry.displayFrame(
            imageWidth: image.width,
            imageHeight: image.height,
            in: bounds.size
        )
        pixelSelection = ImageRegionGeometry.pixelRect(
            selection: selection,
            displayFrame: frame,
            imageWidth: image.width,
            imageHeight: image.height
        )
        picker?.updateSelection(pixelSelection)
        needsDisplay = true
    }
}

private final class ImageRegionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
