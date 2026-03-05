import AppKit
import Carbon

struct Hotkey: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    init(shortcutKey: ShortcutKey) {
        self.keyCode = shortcutKey.keyCode
        self.modifiers = shortcutKey.modifierFlag
    }

    func isModifierActive(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        return event.modifierFlags.contains(modifiers)
    }
}

final class HotkeyListener {
    var hotkey: Hotkey
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func start() {
        // Monitor installation is handled centrally in VibeScribeApp.
    }

    func stop() {
        // Monitor removal is handled centrally in VibeScribeApp.
    }

    func handle(event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else { return }
        if hotkey.isModifierActive(event) {
            onKeyDown?()
        } else {
            onKeyUp?()
        }
    }
}
