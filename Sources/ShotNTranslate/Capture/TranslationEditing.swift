import AppKit
import ShotNTranslateCore
import SwiftUI

enum TranslationInk {
    static let fontSize: CGFloat = 16

    static func plain(_ text: String, isDark: Bool) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineSpacing = 3
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: defaultColor(isDark: isDark),
            .paragraphStyle: style
        ])
    }

    static func defaultColor(isDark: Bool) -> NSColor {
        isDark ? .white : .black
    }

    static func isInk(_ color: NSColor?, matchingDark: Bool) -> Bool {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return true }
        let bright = rgb.redComponent > 0.92 && rgb.greenComponent > 0.92 && rgb.blueComponent > 0.92
        let dark = rgb.redComponent < 0.08 && rgb.greenComponent < 0.08 && rgb.blueComponent < 0.08
        return matchingDark ? bright : dark
    }
}

struct EditorColorChoice: Identifiable {
    var id: String
    var key: L10nKey
    var color: NSColor
}

enum EditorColorChoices {
    static let all: [EditorColorChoice] = [
        EditorColorChoice(id: "black", key: .colorBlack, color: .black),
        EditorColorChoice(id: "white", key: .colorWhite, color: .white),
        EditorColorChoice(id: "red", key: .colorRed, color: .systemRed),
        EditorColorChoice(id: "orange", key: .colorOrange, color: .systemOrange),
        EditorColorChoice(id: "green", key: .colorGreen, color: .systemGreen),
        EditorColorChoice(id: "blue", key: .colorBlue, color: .systemBlue)
    ]
}

/// Applies basic word-processor commands to the translation text view.
@MainActor
final class TranslationEditingController {
    weak var textView: NSTextView?
    var onChange: ((NSAttributedString) -> Void)?
    var suppressChange = false

    func toggleTrait(_ trait: NSFontTraitMask) {
        edit { storage, range in
            if range.length == 0 {
                updateTyping { attributes in
                    let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: TranslationInk.fontSize)
                    attributes[.font] = toggled(font, trait: trait)
                }
                return
            }
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: TranslationInk.fontSize)
                storage.addAttribute(.font, value: toggled(font, trait: trait), range: subrange)
            }
        }
    }

    func toggleUnderline() {
        edit { storage, range in
            if range.length == 0 {
                updateTyping { attributes in
                    let current = attributes[.underlineStyle] as? Int ?? 0
                    attributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                }
                return
            }
            var anyPlain = false
            storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
                let style = value as? Int ?? 0
                if style == 0 { anyPlain = true }
            }
            let next = anyPlain ? NSUnderlineStyle.single.rawValue : 0
            storage.addAttribute(.underlineStyle, value: next, range: range)
        }
    }

    func align(_ alignment: NSTextAlignment) {
        edit { storage, range in
            let paragraphs = (storage.string as NSString).paragraphRange(for: range)
            storage.enumerateAttribute(.paragraphStyle, in: paragraphs, options: []) { value, subrange, _ in
                let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()
                style.alignment = alignment
                storage.addAttribute(.paragraphStyle, value: style, range: subrange)
            }
            updateTyping { attributes in
                let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()
                style.alignment = alignment
                attributes[.paragraphStyle] = style
            }
        }
    }

    func apply(color: NSColor) {
        edit { storage, range in
            if range.length == 0 {
                updateTyping { $0[.foregroundColor] = color }
                return
            }
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    func changeSize(by delta: CGFloat) {
        edit { storage, range in
            func resized(_ font: NSFont) -> NSFont {
                let size = min(72, max(10, font.pointSize + delta))
                return NSFontManager.shared.convert(font, toSize: size)
            }
            if range.length == 0 {
                updateTyping { attributes in
                    let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: TranslationInk.fontSize)
                    attributes[.font] = resized(font)
                }
                return
            }
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: TranslationInk.fontSize)
                storage.addAttribute(.font, value: resized(font), range: subrange)
            }
        }
    }

    func retint(toDark: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        let previousWasDark = !toDark
        let next = TranslationInk.defaultColor(isDark: toDark)
        storage.beginEditing()
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.foregroundColor, in: full, options: []) { value, range, _ in
            if TranslationInk.isInk(value as? NSColor, matchingDark: previousWasDark) {
                storage.addAttribute(.foregroundColor, value: next, range: range)
            }
        }
        storage.endEditing()
        var typing = textView.typingAttributes
        if TranslationInk.isInk(typing[.foregroundColor] as? NSColor, matchingDark: previousWasDark) {
            typing[.foregroundColor] = next
        }
        textView.typingAttributes = typing
        applySurface(isDark: toDark)
        let copy = NSAttributedString(attributedString: storage)
        Task { @MainActor in
            self.onChange?(copy)
        }
    }

    func applySurface(isDark: Bool) {
        guard let textView else { return }
        textView.drawsBackground = true
        textView.backgroundColor = TranslationInk.defaultColor(isDark: !isDark)
        textView.insertionPointColor = TranslationInk.defaultColor(isDark: isDark)
    }

    private func toggled(_ font: NSFont, trait: NSFontTraitMask) -> NSFont {
        let manager = NSFontManager.shared
        if manager.traits(of: font).contains(trait) {
            return manager.convert(font, toNotHaveTrait: trait)
        }
        return manager.convert(font, toHaveTrait: trait)
    }

    private func edit(_ change: (NSTextStorage, NSRange) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        textView.window?.makeFirstResponder(textView)
        storage.beginEditing()
        change(storage, textView.selectedRange())
        storage.endEditing()
        textView.didChangeText()
        publish()
    }

    private func updateTyping(_ change: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let textView else { return }
        var attributes = textView.typingAttributes
        change(&attributes)
        textView.typingAttributes = attributes
    }

    private func publish() {
        guard let storage = textView?.textStorage else { return }
        onChange?(NSAttributedString(attributedString: storage))
    }
}

struct TranslationTextEditor: NSViewRepresentable {
    var text: NSAttributedString
    var reloadToken: UUID
    var isDark: Bool
    var controller: TranslationEditingController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.usesFontPanel = true
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(text)
        context.coordinator.reloadToken = reloadToken
        context.coordinator.appliedDark = isDark
        controller.textView = textView
        controller.applySurface(isDark: isDark)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        if context.coordinator.reloadToken != reloadToken {
            controller.suppressChange = true
            textView.textStorage?.setAttributedString(text)
            controller.suppressChange = false
            context.coordinator.reloadToken = reloadToken
        }
        if context.coordinator.appliedDark != isDark {
            context.coordinator.appliedDark = isDark
            controller.retint(toDark: isDark)
        } else {
            controller.applySurface(isDark: isDark)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var controller: TranslationEditingController
        var reloadToken = UUID()
        var appliedDark: Bool?

        init(controller: TranslationEditingController) {
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            guard !controller.suppressChange,
                  let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }
            controller.onChange?(NSAttributedString(attributedString: storage))
        }
    }
}
