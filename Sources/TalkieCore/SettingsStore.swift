import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let apiKeyKey = "Talkie.ApiKey"
    static let deepgramLanguageKey = "Talkie.DeepgramLanguage"
    static let starredDeepgramLanguagesKey = "Talkie.StarredDeepgramLanguages"
    static let historyLimitKey = "Talkie.HistoryLimit"
    static let shortcutsKey = "Talkie.Shortcuts"
    static let openRouterApiKeyKey = "Talkie.OpenRouterApiKey"
    static let openRouterModelKey = "Talkie.OpenRouterModel"
    static let promptsKey = "Talkie.Prompts"
    static let legacyEnhancementPromptsKey = "Talkie.EnhancementPrompts"
    static let escToCancelRecordingKey = "Talkie.EscToCancelRecording"
    static let playSoundEffectsKey = "Talkie.PlaySoundEffects"
    static let muteMediaDuringRecordingKey = "Talkie.MuteMediaDuringRecording"
    static let restoreClipboardAfterPasteKey = "Talkie.RestoreClipboardAfterPaste"
    static let overlayPositionKey = "Talkie.OverlayPosition"
    static let audioInputSelectionKey = "Talkie.AudioInputSelection"

    private let defaults: UserDefaults

    @Published var apiKey: String {
        didSet {
            defaults.set(apiKey, forKey: Self.apiKeyKey)
        }
    }

    @Published var shortcuts: [ShortcutConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(shortcuts) {
                defaults.set(data, forKey: Self.shortcutsKey)
            }
        }
    }

    @Published var openRouterApiKey: String {
        didSet {
            defaults.set(openRouterApiKey, forKey: Self.openRouterApiKeyKey)
        }
    }

    @Published var openRouterModel: String {
        didSet {
            defaults.set(openRouterModel, forKey: Self.openRouterModelKey)
        }
    }

    @Published var prompts: [PromptConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(prompts) {
                defaults.set(data, forKey: Self.promptsKey)
            }
        }
    }

    @Published var escToCancelRecording: Bool {
        didSet {
            defaults.set(escToCancelRecording, forKey: Self.escToCancelRecordingKey)
        }
    }

    @Published var playSoundEffects: Bool {
        didSet {
            defaults.set(playSoundEffects, forKey: Self.playSoundEffectsKey)
        }
    }

    @Published var muteMediaDuringRecording: Bool {
        didSet {
            defaults.set(muteMediaDuringRecording, forKey: Self.muteMediaDuringRecordingKey)
        }
    }

    @Published var restoreClipboardAfterPaste: Bool {
        didSet {
            defaults.set(restoreClipboardAfterPaste, forKey: Self.restoreClipboardAfterPasteKey)
        }
    }

    @Published var overlayPosition: OverlayPosition {
        didSet {
            defaults.set(overlayPosition.rawValue, forKey: Self.overlayPositionKey)
        }
    }

    @Published var audioInputSelection: AudioInputSelection {
        didSet {
            defaults.set(audioInputSelection.storedValue, forKey: Self.audioInputSelectionKey)
        }
    }

    @Published var deepgramLanguage: DeepgramLanguage {
        didSet {
            defaults.set(deepgramLanguage.rawValue, forKey: Self.deepgramLanguageKey)
        }
    }

    @Published var starredDeepgramLanguages: [DeepgramLanguage] {
        didSet {
            let normalized = DeepgramLanguage.normalizedStarredLanguages(
                starredDeepgramLanguages,
                fallback: oldValue.isEmpty ? DeepgramLanguage.defaultStarredLanguages : oldValue
            )

            if normalized != starredDeepgramLanguages {
                starredDeepgramLanguages = normalized
                return
            }

            defaults.set(normalized.map(\.rawValue), forKey: Self.starredDeepgramLanguagesKey)
        }
    }

    @Published var historyLimit: HistoryLimit {
        didSet {
            defaults.set(historyLimit.rawValue, forKey: Self.historyLimitKey)
        }
    }

    var hasOpenRouterCredentials: Bool {
        !openRouterApiKey.trimmed.isEmpty && !openRouterModel.trimmed.isEmpty
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        apiKey = defaults.string(forKey: Self.apiKeyKey) ?? ""
        escToCancelRecording = (defaults.object(forKey: Self.escToCancelRecordingKey) as? Bool) ?? true
        playSoundEffects = (defaults.object(forKey: Self.playSoundEffectsKey) as? Bool) ?? false
        muteMediaDuringRecording = (defaults.object(forKey: Self.muteMediaDuringRecordingKey) as? Bool) ?? false
        restoreClipboardAfterPaste = (defaults.object(forKey: Self.restoreClipboardAfterPasteKey) as? Bool) ?? false

        let savedPosition = defaults.string(forKey: Self.overlayPositionKey)
        overlayPosition = savedPosition.flatMap(OverlayPosition.init(rawValue:)) ?? .top

        audioInputSelection = AudioInputSelection(
            storedValue: defaults.string(forKey: Self.audioInputSelectionKey)
        )

        let savedLanguage = defaults.string(forKey: Self.deepgramLanguageKey)
        deepgramLanguage = savedLanguage.flatMap(DeepgramLanguage.init(rawValue:)) ?? .automatic
        starredDeepgramLanguages = DeepgramLanguage.starredLanguages(
            from: defaults.stringArray(forKey: Self.starredDeepgramLanguagesKey)
        )

        let savedLimit = defaults.integer(forKey: Self.historyLimitKey)
        historyLimit = HistoryLimit(rawValue: savedLimit) ?? .ten

        if let data = defaults.data(forKey: Self.shortcutsKey),
           let decoded = try? JSONDecoder().decode([ShortcutConfig].self, from: data),
           !decoded.isEmpty {
            shortcuts = decoded
        } else {
            shortcuts = [ShortcutConfig.makeDefault()]
        }

        openRouterApiKey = defaults.string(forKey: Self.openRouterApiKeyKey) ?? ""
        openRouterModel = defaults.string(forKey: Self.openRouterModelKey) ?? ""

        if let data = defaults.data(forKey: Self.promptsKey),
           let decoded = try? JSONDecoder().decode([PromptConfig].self, from: data) {
            prompts = decoded
        } else {
            prompts = []
            PromptRoutingService.migrateLegacyEnhancementPromptsIfNeeded(
                defaults: defaults,
                shortcuts: &shortcuts,
                prompts: &prompts
            )
        }
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }
}

enum HistoryLimit: Int, CaseIterable, Identifiable {
    case none = 0
    case ten = 10
    case hundred = 100

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .ten: "10"
        case .hundred: "100"
        }
    }
}
