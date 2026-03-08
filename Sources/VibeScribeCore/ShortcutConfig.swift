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
    case click
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Hold"
        case .click: return "Click"
        case .both: return "Both"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "doubleClick" {
            self = .click
            return
        }
        guard let mode = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot initialize ShortcutMode from invalid value \(rawValue)"
            )
        }
        self = mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ShortcutConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var key: ShortcutKey
    var mode: ShortcutMode
    var promptID: UUID?
    var appPromptOverrides: [AppPromptOverride]

    init(
        id: UUID,
        key: ShortcutKey,
        mode: ShortcutMode,
        promptID: UUID? = nil,
        appPromptOverrides: [AppPromptOverride] = []
    ) {
        self.id = id
        self.key = key
        self.mode = mode
        self.promptID = promptID
        self.appPromptOverrides = appPromptOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case mode
        case promptID
        case appPromptOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        key = try container.decode(ShortcutKey.self, forKey: .key)
        mode = try container.decode(ShortcutMode.self, forKey: .mode)
        promptID = try container.decodeIfPresent(UUID.self, forKey: .promptID)
        appPromptOverrides = try container.decodeIfPresent([AppPromptOverride].self, forKey: .appPromptOverrides) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(promptID, forKey: .promptID)
        try container.encode(appPromptOverrides, forKey: .appPromptOverrides)
    }

    static func makeDefault() -> ShortcutConfig {
        ShortcutConfig(id: UUID(), key: .rightOption, mode: .both)
    }
}

struct AppPromptOverride: Codable, Identifiable, Equatable {
    var id: UUID
    var appBundleIdentifier: String
    var appDisplayName: String
    var promptID: UUID

    init(
        id: UUID = UUID(),
        appBundleIdentifier: String,
        appDisplayName: String,
        promptID: UUID
    ) {
        self.id = id
        self.appBundleIdentifier = appBundleIdentifier
        self.appDisplayName = appDisplayName
        self.promptID = promptID
    }

    var normalizedAppBundleIdentifier: String? {
        Self.normalizeBundleIdentifier(appBundleIdentifier)
    }

    static func normalizeBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        let trimmed = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

struct PromptConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var content: String

    static func makeDefault() -> PromptConfig {
        PromptConfig(
            id: UUID(),
            name: "Clean up",
            content: """
            Clean up the following transcription. Fix spelling, grammar, punctuation, and formatting only. \
            Do not change, remove, or rephrase any of the original words or meaning. Keep the speaker's \
            voice and intent exactly as-is.

            Remove filler words (um, uh, you know) and false starts only when they add no meaning. \
            Add paragraph breaks where topics shift naturally.

            Return only the cleaned transcription as plain text. No explanations, no quotes, no HTML tags, \
            no markdown, no preamble, no closing remarks. Just the text.
            """
        )
    }
}
