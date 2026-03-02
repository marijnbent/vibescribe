import Carbon
import XCTest
@testable import VibeScribeCore

final class ShortcutConfigTests: XCTestCase {

    // MARK: - ShortcutKey

    func testShortcutKeyKeyCodes() {
        XCTAssertEqual(ShortcutKey.fn.keyCode, 0x3F)
        XCTAssertEqual(ShortcutKey.leftControl.keyCode, UInt16(kVK_Control))
        XCTAssertEqual(ShortcutKey.leftCommand.keyCode, UInt16(kVK_Command))
        XCTAssertEqual(ShortcutKey.rightCommand.keyCode, UInt16(kVK_RightCommand))
        XCTAssertEqual(ShortcutKey.rightOption.keyCode, UInt16(kVK_RightOption))
    }

    func testShortcutKeyDisplayNames() {
        XCTAssertEqual(ShortcutKey.fn.displayName, "Fn")
        XCTAssertEqual(ShortcutKey.leftControl.displayName, "Left Control")
        XCTAssertEqual(ShortcutKey.leftCommand.displayName, "Left Command")
        XCTAssertEqual(ShortcutKey.rightCommand.displayName, "Right Command")
        XCTAssertEqual(ShortcutKey.rightOption.displayName, "Right Option")
    }

    func testShortcutKeyModifierFlags() {
        XCTAssertTrue(ShortcutKey.fn.modifierFlag.contains(.function))
        XCTAssertTrue(ShortcutKey.leftControl.modifierFlag.contains(.control))
        XCTAssertTrue(ShortcutKey.leftCommand.modifierFlag.contains(.command))
        XCTAssertTrue(ShortcutKey.rightCommand.modifierFlag.contains(.command))
        XCTAssertTrue(ShortcutKey.rightOption.modifierFlag.contains(.option))
    }

    func testShortcutKeyAllCases() {
        XCTAssertEqual(ShortcutKey.allCases.count, 5)
    }

    func testShortcutKeyIdentifiable() {
        for key in ShortcutKey.allCases {
            XCTAssertEqual(key.id, key.rawValue)
        }
    }

    func testShortcutKeyCodableRoundTrip() throws {
        for key in ShortcutKey.allCases {
            let data = try JSONEncoder().encode(key)
            let decoded = try JSONDecoder().decode(ShortcutKey.self, from: data)
            XCTAssertEqual(decoded, key)
        }
    }

    // MARK: - ShortcutMode

    func testShortcutModeDisplayNames() {
        XCTAssertEqual(ShortcutMode.hold.displayName, "Hold")
        XCTAssertEqual(ShortcutMode.doubleClick.displayName, "Double Click")
        XCTAssertEqual(ShortcutMode.both.displayName, "Both")
    }

    func testShortcutModeAllCases() {
        XCTAssertEqual(ShortcutMode.allCases.count, 3)
    }

    func testShortcutModeIdentifiable() {
        for mode in ShortcutMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    func testShortcutModeCodableRoundTrip() throws {
        for mode in ShortcutMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(ShortcutMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - ShortcutConfig

    func testMakeDefault() {
        let config = ShortcutConfig.makeDefault()
        XCTAssertEqual(config.key, .rightOption)
        XCTAssertEqual(config.mode, .both)
    }

    func testMakeDefaultGeneratesUniqueIDs() {
        let a = ShortcutConfig.makeDefault()
        let b = ShortcutConfig.makeDefault()
        XCTAssertNotEqual(a.id, b.id)
    }

    func testShortcutConfigCodableRoundTrip() throws {
        let config = ShortcutConfig(id: UUID(), key: .leftControl, mode: .doubleClick)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ShortcutConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testShortcutConfigArrayCodableRoundTrip() throws {
        let configs = [
            ShortcutConfig(id: UUID(), key: .rightOption, mode: .both),
            ShortcutConfig(id: UUID(), key: .fn, mode: .hold),
            ShortcutConfig(id: UUID(), key: .leftCommand, mode: .doubleClick),
        ]
        let data = try JSONEncoder().encode(configs)
        let decoded = try JSONDecoder().decode([ShortcutConfig].self, from: data)
        XCTAssertEqual(decoded, configs)
    }

    func testShortcutConfigEquality() {
        let id = UUID()
        let a = ShortcutConfig(id: id, key: .fn, mode: .hold)
        let b = ShortcutConfig(id: id, key: .fn, mode: .hold)
        XCTAssertEqual(a, b)

        let c = ShortcutConfig(id: id, key: .fn, mode: .doubleClick)
        XCTAssertNotEqual(a, c)
    }
}
