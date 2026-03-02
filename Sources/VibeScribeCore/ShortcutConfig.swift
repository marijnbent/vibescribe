import AppKit
import Carbon
import Foundation

enum ShortcutKey: String, Codable, CaseIterable, Identifiable {
    case fn
    case leftControl
    case leftCommand
    case rightCommand
    case rightOption

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .fn: return 0x3F
        case .leftControl: return UInt16(kVK_Control)
        case .leftCommand: return UInt16(kVK_Command)
        case .rightCommand: return UInt16(kVK_RightCommand)
        case .rightOption: return UInt16(kVK_RightOption)
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .leftControl: return .control
        case .leftCommand: return .command
        case .rightCommand: return .command
        case .rightOption: return .option
        }
    }

    var displayName: String {
        switch self {
        case .fn: return "Fn"
        case .leftControl: return "Left Control"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        case .rightOption: return "Right Option"
        }
    }
}

enum ShortcutMode: String, Codable, CaseIterable, Identifiable {
    case hold
    case doubleClick
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Hold"
        case .doubleClick: return "Double Click"
        case .both: return "Both"
        }
    }
}

struct ShortcutConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var key: ShortcutKey
    var mode: ShortcutMode

    static func makeDefault() -> ShortcutConfig {
        ShortcutConfig(id: UUID(), key: .rightOption, mode: .both)
    }
}
