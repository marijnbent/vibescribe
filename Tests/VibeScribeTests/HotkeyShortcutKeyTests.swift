import Carbon
import XCTest
@testable import VibeScribeCore

final class HotkeyShortcutKeyTests: XCTestCase {

    func testInitFromShortcutKeySetsModifierOnlyTrigger() {
        for key in ShortcutKey.allCases {
            let hotkey = Hotkey(shortcutKey: key)
            XCTAssertEqual(hotkey.trigger, .modifierOnly, "Expected modifierOnly for \(key)")
        }
    }

    func testInitFromShortcutKeyMapsKeyCode() {
        for key in ShortcutKey.allCases {
            let hotkey = Hotkey(shortcutKey: key)
            XCTAssertEqual(hotkey.keyCode, key.keyCode, "Key code mismatch for \(key)")
        }
    }

    func testInitFromShortcutKeyMapsModifiers() {
        for key in ShortcutKey.allCases {
            let hotkey = Hotkey(shortcutKey: key)
            XCTAssertEqual(hotkey.modifiers, key.modifierFlag, "Modifier flag mismatch for \(key)")
        }
    }

    func testDisplayNameForAllShortcutKeys() {
        let expectations: [(ShortcutKey, String)] = [
            (.fn, "Fn"),
            (.leftControl, "Left Control"),
            (.leftCommand, "Left Command"),
            (.rightCommand, "Right Command"),
            (.rightOption, "Right Option"),
        ]
        for (key, expected) in expectations {
            let hotkey = Hotkey(shortcutKey: key)
            XCTAssertEqual(hotkey.displayName, expected)
        }
    }

    func testPushToTalkDefaultMatchesRightOption() {
        let fromKey = Hotkey(shortcutKey: .rightOption)
        let defaultHotkey = Hotkey.pushToTalkDefault
        XCTAssertEqual(fromKey.trigger, defaultHotkey.trigger)
        XCTAssertEqual(fromKey.keyCode, defaultHotkey.keyCode)
        XCTAssertEqual(fromKey.modifiers, defaultHotkey.modifiers)
    }
}
