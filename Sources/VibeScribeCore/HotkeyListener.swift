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

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else { return }
        if hotkey.isModifierActive(event) {
            onKeyDown?()
        } else {
            onKeyUp?()
        }
    }
}
