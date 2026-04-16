import Foundation

@MainActor
final class PromptRoutingService {
    struct ResolvedPromptSelection {
        let prompt: PromptConfig
        let isForActiveApp: Bool
    }

    func promptContent(
        forShortcutID shortcutID: UUID,
        settings: SettingsStore,
        activeAppBundleIdentifier: String? = nil
    ) -> String? {
        resolvedPromptSelection(
            forShortcutID: shortcutID,
            settings: settings,
            activeAppBundleIdentifier: activeAppBundleIdentifier
        )?.prompt.content
    }

    func resolvedPrompt(
        forShortcutID shortcutID: UUID,
        settings: SettingsStore,
        activeAppBundleIdentifier: String? = nil
    ) -> PromptConfig? {
        resolvedPromptSelection(
            forShortcutID: shortcutID,
            settings: settings,
            activeAppBundleIdentifier: activeAppBundleIdentifier
        )?.prompt
    }

    func resolvedEnhancementPrompt(
        forShortcutID shortcutID: UUID,
        settings: SettingsStore,
        activeAppBundleIdentifier: String? = nil
    ) -> EnhancementPromptContext? {
        guard let selection = resolvedPromptSelection(
            forShortcutID: shortcutID,
            settings: settings,
            activeAppBundleIdentifier: activeAppBundleIdentifier
        ) else {
            return nil
        }

        return EnhancementPromptContext(
            name: selection.prompt.displayName,
            content: selection.prompt.content,
            isForActiveApp: selection.isForActiveApp
        )
    }

    func resolvedPromptSelection(
        forShortcutID shortcutID: UUID,
        settings: SettingsStore,
        activeAppBundleIdentifier: String? = nil
    ) -> ResolvedPromptSelection? {
        guard let shortcut = settings.shortcuts.first(where: { $0.id == shortcutID }) else {
            return nil
        }

        if let normalizedBundleIdentifier = AppPromptOverride.normalizeBundleIdentifier(activeAppBundleIdentifier),
           let overridePromptID = shortcut.appPromptOverrides.first(where: {
               $0.normalizedAppBundleIdentifier == normalizedBundleIdentifier
           })?.promptID,
           let prompt = settings.prompts.first(where: { $0.id == overridePromptID }) {
            return ResolvedPromptSelection(prompt: prompt, isForActiveApp: true)
        }

        if let promptID = shortcut.promptID,
           let prompt = settings.prompts.first(where: { $0.id == promptID }) {
            return ResolvedPromptSelection(prompt: prompt, isForActiveApp: false)
        }

        return nil
    }

    func deletePrompt(id: UUID, settings: SettingsStore) {
        settings.prompts.removeAll { $0.id == id }
        for index in settings.shortcuts.indices where settings.shortcuts[index].promptID == id {
            settings.shortcuts[index].promptID = nil
        }
        for index in settings.shortcuts.indices {
            settings.shortcuts[index].appPromptOverrides.removeAll { $0.promptID == id }
        }
    }

    func upsertAppPromptOverride(
        shortcutID: UUID,
        appBundleIdentifier: String,
        appDisplayName: String,
        promptID: UUID? = nil,
        settings: SettingsStore
    ) {
        guard let normalizedBundleIdentifier = AppPromptOverride.normalizeBundleIdentifier(appBundleIdentifier),
              let shortcutIndex = settings.shortcuts.firstIndex(where: { $0.id == shortcutID }) else {
            return
        }

        let resolvedPromptID = promptID ?? settings.shortcuts[shortcutIndex].promptID ?? settings.prompts.first?.id
        guard let resolvedPromptID else { return }

        let cleanedDisplayName = appDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanedDisplayName.isEmpty ? appBundleIdentifier : cleanedDisplayName

        if let overrideIndex = settings.shortcuts[shortcutIndex].appPromptOverrides.firstIndex(where: {
            $0.normalizedAppBundleIdentifier == normalizedBundleIdentifier
        }) {
            settings.shortcuts[shortcutIndex].appPromptOverrides[overrideIndex].appBundleIdentifier = normalizedBundleIdentifier
            settings.shortcuts[shortcutIndex].appPromptOverrides[overrideIndex].appDisplayName = displayName
            settings.shortcuts[shortcutIndex].appPromptOverrides[overrideIndex].promptID = resolvedPromptID
        } else {
            settings.shortcuts[shortcutIndex].appPromptOverrides.append(
                AppPromptOverride(
                    appBundleIdentifier: normalizedBundleIdentifier,
                    appDisplayName: displayName,
                    promptID: resolvedPromptID
                )
            )
        }

        settings.shortcuts[shortcutIndex].appPromptOverrides.sort {
            let nameOrder = $0.appDisplayName.localizedCaseInsensitiveCompare($1.appDisplayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return $0.appBundleIdentifier.localizedCaseInsensitiveCompare($1.appBundleIdentifier) == .orderedAscending
        }
    }

    static func migrateLegacyEnhancementPromptsIfNeeded(
        defaults: UserDefaults,
        shortcuts: inout [ShortcutConfig],
        prompts: inout [PromptConfig]
    ) {
        guard let data = defaults.data(forKey: SettingsStore.legacyEnhancementPromptsKey),
              let legacyPrompts = try? JSONDecoder().decode([String: String].self, from: data),
              !legacyPrompts.isEmpty else {
            return
        }

        var migratedPrompts: [PromptConfig] = []
        var promptIDByShortcutID: [UUID: UUID] = [:]
        for (shortcutIDRaw, content) in legacyPrompts.sorted(by: { $0.key < $1.key }) {
            guard let shortcutID = UUID(uuidString: shortcutIDRaw) else { continue }
            let trimmed = content.trimmed
            guard !trimmed.isEmpty else { continue }

            let prompt = PromptConfig(id: UUID(), name: "Migrated Prompt", content: trimmed)
            migratedPrompts.append(prompt)
            promptIDByShortcutID[shortcutID] = prompt.id
        }

        prompts = migratedPrompts
        if !promptIDByShortcutID.isEmpty {
            for index in shortcuts.indices {
                if let promptID = promptIDByShortcutID[shortcuts[index].id] {
                    shortcuts[index].promptID = promptID
                }
            }
        }

        defaults.removeObject(forKey: SettingsStore.legacyEnhancementPromptsKey)
    }
}
