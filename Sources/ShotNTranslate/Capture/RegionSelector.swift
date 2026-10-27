import AppKit
import Carbon

@MainActor
final class RegionSelector {
    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var keyMonitor: Any?

    func select(instruction: String) async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(instruction: instruction)
        }
    }

    private func present(instruction: String) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            DispatchQueue.main.async { self.complete(nil) }
            return
        }

        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        var keyWindow: NSWindow?
        for screen in screens {
            let panel = SelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.sharingType = .none
            panel.isMovable = false
            panel.animationBehavior = .none
            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.selector = self
            view.instruction = instruction
            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            windows.append(panel)
            if screen.frame.contains(mouse) {
                keyWindow = panel
            }
        }
        let key = keyWindow ?? windows[0]
        key.makeKeyAndOrderFront(nil)
        if let view = key.contentView {
            key.makeFirstResponder(view)
        }
        NSCursor.crosshair.set()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            MainActor.assumeIsolated {
                self?.complete(nil)
            }
            return nil
        }
    }

    func complete(_ rect: CGRect?) {
        guard continuation != nil else { return }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        windows.forEach {
            $0.alphaValue = 0
            $0.orderOut(nil)
        }
        windows.removeAll()
        NSCursor.arrow.set()
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: rect)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayView: NSView {
    weak var selector: RegionSelector?
    var instruction = ""
    private var anchor: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            selector?.complete(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        anchor = point
        current = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let local = selectionRect(), local.width >= 12, local.height >= 12 else {
            selector?.complete(nil)
            return
        }
        let screenRect = window?.convertToScreen(local) ?? .zero
        selector?.complete(screenRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.35)
        if let selection = selectionRect(), selection.width > 1, selection.height > 1 {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: selection))
            path.windingRule = .evenOdd
            dim.setFill()
            path.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
        } else {
            dim.setFill()
            bounds.fill()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
        let textRect = NSRect(x: 28, y: bounds.height - 88, width: bounds.width - 56, height: 56)
        (instruction as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func selectionRect() -> CGRect? {
        guard let anchor, let current else { return nil }
        return CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(anchor.x - current.x),
            height: abs(anchor.y - current.y)
        )
    }
}
