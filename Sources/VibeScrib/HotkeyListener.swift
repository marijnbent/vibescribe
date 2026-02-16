import AppKit
import Carbon

enum HotkeyTrigger: Equatable {
    case keyCombo
    case modifierOnly
}

struct Hotkey: Equatable {
    let trigger: HotkeyTrigger
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    static let pushToTalkDefault = Hotkey(
        trigger: .modifierOnly,
        keyCode: UInt16(kVK_RightOption),
        modifiers: [.option]
    )

    var displayName: String {
        switch trigger {
        case .modifierOnly:
            return Hotkey.keyName(for: keyCode)
        case .keyCombo:
            let modifierNames = [
                modifiers.contains(.control) ? "Ctrl" : nil,
                modifiers.contains(.option) ? "Opt" : nil,
                modifiers.contains(.shift) ? "Shift" : nil,
                modifiers.contains(.command) ? "Cmd" : nil,
            ].compactMap { $0 }

            let keyName = Hotkey.keyName(for: keyCode)
            if modifierNames.isEmpty {
                return keyName
            }

            return modifierNames.joined(separator: "+") + "+" + keyName
        }
    }

    func matchesKeyEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let normalized = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let required = modifiers.intersection(.deviceIndependentFlagsMask)
        return normalized == required
    }

    func isModifierActive(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        return event.modifierFlags.contains(modifiers)
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_RightOption:
            return "Right Option"
        case kVK_Option:
            return "Left Option"
        default:
            return "KeyCode(\(keyCode))"
        }
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

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
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
        switch hotkey.trigger {
        case .modifierOnly:
            guard event.type == .flagsChanged else { return }
            guard event.keyCode == hotkey.keyCode else { return }
            if hotkey.isModifierActive(event) {
                onKeyDown?()
            } else {
                onKeyUp?()
            }
        case .keyCombo:
            guard hotkey.matchesKeyEvent(event) else { return }
            switch event.type {
            case .keyDown:
                onKeyDown?()
            case .keyUp:
                onKeyUp?()
            default:
                break
            }
        }
    }
}
