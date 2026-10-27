import AppKit
import Observation
import ShotNTranslateCore

@MainActor
enum ShortcutDebounce {
    private static var last: [String: Date] = [:]

    static func allow(_ key: String, interval: TimeInterval = 0.35) -> Bool {
        let now = Date()
        if let previous = last[key], now.timeIntervalSince(previous) < interval {
            return false
        }
        last[key] = now
        return true
    }
}

@MainActor
@Observable
final class ShortcutRouter {
    let translator: ScreenshotTranslator
    let updateCenter: UpdateCenter
    var openUpdateHistory: @MainActor () -> Void = {}

    init(translator: ScreenshotTranslator, updateCenter: UpdateCenter) {
        self.translator = translator
        self.updateCenter = updateCenter
    }

    func run(_ function: ShortcutFunction) {
        guard ShortcutDebounce.allow(function.rawValue) else { return }
        switch function {
        case .translateSelection:
            Task { await translator.translateSelection() }
        case .checkForUpdates:
            showUpdateHistory(checking: true)
        case .showUpdateHistory:
            showUpdateHistory(checking: false)
        }
    }

    func showUpdateHistory(checking: Bool) {
        NSApp.activate()
        openUpdateHistory()
        guard checking else { return }
        Task { await updateCenter.checkForUpdates() }
    }
}
