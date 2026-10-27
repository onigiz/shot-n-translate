import AppKit
import Carbon
import ShotNTranslateCore

private func hotKeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = withUnsafeMutableBytes(of: &hotKeyID) { buffer in
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            buffer.count,
            nil,
            buffer.baseAddress
        )
    }
    guard status == noErr else { return status }
    let identifier = hotKeyID.id
    DispatchQueue.main.async {
        GlobalShortcutCenter.shared.handle(id: identifier)
    }
    return noErr
}

@MainActor
final class GlobalShortcutCenter {
    static let shared = GlobalShortcutCenter()

    private var router: ShortcutRouter?
    private var installed = false
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let keyCodes: [String: UInt32] = [
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "h": UInt32(kVK_ANSI_H)
    ]

    func install(router: ShortcutRouter) {
        self.router = router
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            nil,
            &handler
        )

        let signature = OSType(0x536E5472)
        for (offset, spec) in ShortcutCatalog.items.enumerated() {
            guard let keyCode = keyCodes[spec.key] else { continue }
            var modifiers: UInt32 = 0
            if spec.command { modifiers |= UInt32(cmdKey) }
            if spec.shift { modifiers |= UInt32(shiftKey) }
            var hotKey: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: signature, id: UInt32(offset + 1))
            var status = RegisterEventHotKey(
                keyCode,
                modifiers,
                identifier,
                GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive),
                &hotKey
            )
            if status != noErr {
                status = RegisterEventHotKey(
                    keyCode,
                    modifiers,
                    identifier,
                    GetApplicationEventTarget(),
                    0,
                    &hotKey
                )
            }
            if status == noErr, let hotKey {
                hotKeys.append(hotKey)
            }
        }
    }

    func handle(id: UInt32) {
        let index = Int(id) - 1
        guard ShortcutCatalog.items.indices.contains(index) else { return }
        router?.run(ShortcutCatalog.items[index].function)
    }
}
