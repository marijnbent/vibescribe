import Carbon
import XCTest
@testable import TalkieCore

final class HotkeyShortcutKeyTests: XCTestCase {

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
}
