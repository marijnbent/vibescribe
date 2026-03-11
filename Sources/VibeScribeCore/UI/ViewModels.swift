import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class GeneralSettingsViewModel: ObservableObject {
    private let settingsStore: SettingsStore
    private let permissionService: PermissionService
    private var cancellables = Set<AnyCancellable>()

    init(settingsStore: SettingsStore, permissionService: PermissionService) {
        self.settingsStore = settingsStore
        self.permissionService = permissionService
        bind()
    }

    var microphonePermission: PermissionStatus { permissionService.microphonePermission }
    var accessibilityPermission: PermissionStatus { permissionService.accessibilityPermission }
    var availableAudioInputs: [AudioInputDeviceDescriptor] { AudioInputCatalog.availableDevices() }
    var resolvedAudioInputSelection: ResolvedAudioInputSelection {
        AudioInputCatalog.resolvedSelection(settingsStore.audioInputSelection)
    }
    var deepgramLanguage: DeepgramLanguage { settingsStore.deepgramLanguage }
    var starredDeepgramLanguages: [DeepgramLanguage] { settingsStore.starredDeepgramLanguages }
    var audioInputHelpText: String {
        let resolved = resolvedAudioInputSelection

        switch settingsStore.audioInputSelection {
        case .systemDefault:
            if let systemDefaultDevice = resolved.systemDefaultDevice {
                return "Uses the current macOS default microphone: \(systemDefaultDevice.name)."
            }
            return "Uses the current macOS default microphone for new recordings."
        case .device(let uniqueID):
            if let selectedDevice = resolved.selectedDevice {
                return "Uses \(selectedDevice.name) for new recordings, even if your macOS default changes."
            }
            if let systemDefaultDevice = resolved.systemDefaultDevice {
                return "The saved microphone is unavailable. New recordings will fall back to \(systemDefaultDevice.name) until it comes back."
            }
            return "The saved microphone (\(uniqueID)) is unavailable and no fallback input is currently available."
        }
    }

    func binding<Value>(for keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
        Binding(
            get: { self.settingsStore[keyPath: keyPath] },
            set: { self.settingsStore[keyPath: keyPath] = $0 }
        )
    }

    func menuBarLanguages(matching query: String) -> [DeepgramLanguage] {
        DeepgramLanguage.sortedForSettings(
            DeepgramLanguage.allCases.filter { $0.matchesSearch(query) },
            starred: Set(settingsStore.starredDeepgramLanguages)
        )
    }

    func isLanguageStarred(_ language: DeepgramLanguage) -> Bool {
        settingsStore.starredDeepgramLanguages.contains(language)
    }

    func canToggleStarRemoval(for language: DeepgramLanguage) -> Bool {
        !isLanguageStarred(language) || settingsStore.starredDeepgramLanguages.count > 1
    }

    func toggleStar(for language: DeepgramLanguage) {
        if let index = settingsStore.starredDeepgramLanguages.firstIndex(of: language) {
            guard settingsStore.starredDeepgramLanguages.count > 1 else { return }
            settingsStore.starredDeepgramLanguages.remove(at: index)
            return
        }

        settingsStore.starredDeepgramLanguages.append(language)
    }

    func refreshPermissions() {
        permissionService.refreshPermissions()
    }

    func requestMicrophonePermission() {
        permissionService.requestMicrophonePermission()
    }

    func requestAccessibilityPermission() {
        permissionService.requestAccessibilityPermission()
    }

    private func bind() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        permissionService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)
            .merge(with: NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected))
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

@MainActor
final class ShortcutsSettingsViewModel: ObservableObject {
    private let settingsStore: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var shortcuts: [ShortcutConfig] { settingsStore.shortcuts }
    var canAddShortcut: Bool { settingsStore.shortcuts.count < ShortcutKey.allCases.count }

    func binding(forShortcutID shortcutID: UUID) -> Binding<ShortcutConfig>? {
        guard let index = settingsStore.shortcuts.firstIndex(where: { $0.id == shortcutID }) else {
            return nil
        }
        return Binding(
            get: { self.settingsStore.shortcuts[index] },
            set: { self.settingsStore.shortcuts[index] = $0 }
        )
    }

    func usedKeys(excluding shortcutID: UUID) -> Set<ShortcutKey> {
        Set(settingsStore.shortcuts.filter { $0.id != shortcutID }.map(\.key))
    }

    func removeShortcut(id: UUID) {
        settingsStore.shortcuts.removeAll { $0.id == id }
    }

    func addShortcut() {
        let usedKeys = Set(settingsStore.shortcuts.map(\.key))
        if let nextKey = ShortcutKey.allCases.first(where: { !usedKeys.contains($0) }) {
            settingsStore.shortcuts.append(ShortcutConfig(id: UUID(), key: nextKey, mode: .both))
        }
    }
}

@MainActor
final class EnhancementsSettingsViewModel: ObservableObject {
    private let settingsStore: SettingsStore
    private let promptRoutingService: PromptRoutingService
    private var cancellables = Set<AnyCancellable>()

    init(settingsStore: SettingsStore, promptRoutingService: PromptRoutingService) {
        self.settingsStore = settingsStore
        self.promptRoutingService = promptRoutingService
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var prompts: [PromptConfig] { settingsStore.prompts }
    var shortcuts: [ShortcutConfig] { settingsStore.shortcuts }

    func binding<Value>(for keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
        Binding(
            get: { self.settingsStore[keyPath: keyPath] },
            set: { self.settingsStore[keyPath: keyPath] = $0 }
        )
    }

    func bindingForPromptID(_ promptID: UUID) -> Binding<PromptConfig>? {
        guard let index = settingsStore.prompts.firstIndex(where: { $0.id == promptID }) else {
            return nil
        }
        return Binding(
            get: { self.settingsStore.prompts[index] },
            set: { self.settingsStore.prompts[index] = $0 }
        )
    }

    func bindingForShortcutID(_ shortcutID: UUID) -> Binding<ShortcutConfig>? {
        guard let index = settingsStore.shortcuts.firstIndex(where: { $0.id == shortcutID }) else {
            return nil
        }
        return Binding(
            get: { self.settingsStore.shortcuts[index] },
            set: { self.settingsStore.shortcuts[index] = $0 }
        )
    }

    func addPrompt() -> PromptConfig {
        let prompt = PromptConfig.makeDefault()
        settingsStore.prompts.append(prompt)
        return prompt
    }

    func deletePrompt(id: UUID) {
        promptRoutingService.deletePrompt(id: id, settings: settingsStore)
    }

    func upsertAppPromptOverride(
        shortcutID: UUID,
        appBundleIdentifier: String,
        appDisplayName: String,
        promptID: UUID? = nil
    ) {
        promptRoutingService.upsertAppPromptOverride(
            shortcutID: shortcutID,
            appBundleIdentifier: appBundleIdentifier,
            appDisplayName: appDisplayName,
            promptID: promptID,
            settings: settingsStore
        )
    }

    func promptUsageSummary(for promptID: UUID) -> String {
        let defaultShortcutCount = settingsStore.shortcuts.filter { $0.promptID == promptID }.count
        let overrideCount = settingsStore.shortcuts.reduce(0) { partialResult, shortcut in
            partialResult + shortcut.appPromptOverrides.filter { $0.promptID == promptID }.count
        }

        switch (defaultShortcutCount, overrideCount) {
        case (0, 0):
            return "Unused"
        case (_, 0):
            return defaultShortcutCount == 1
                ? "Used as the default for 1 shortcut"
                : "Used as the default for \(defaultShortcutCount) shortcuts"
        case (0, _):
            return overrideCount == 1
                ? "Used by 1 app override"
                : "Used by \(overrideCount) app overrides"
        default:
            let defaultText = defaultShortcutCount == 1
                ? "default for 1 shortcut"
                : "default for \(defaultShortcutCount) shortcuts"
            let overrideText = overrideCount == 1
                ? "1 app override"
                : "\(overrideCount) app overrides"
            return "Used as \(defaultText) and \(overrideText)"
        }
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    private let sessionState: SessionState
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var expandedHistoryEntries: Set<UUID> = []

    init(sessionState: SessionState) {
        self.sessionState = sessionState
        sessionState.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var transcriptHistory: [TranscriptHistoryEntry] {
        sessionState.transcriptHistory
    }

    func isExpanded(_ entryID: UUID) -> Bool {
        expandedHistoryEntries.contains(entryID)
    }

    func toggleExpansion(_ entryID: UUID) {
        if expandedHistoryEntries.contains(entryID) {
            expandedHistoryEntries.remove(entryID)
        } else {
            expandedHistoryEntries.insert(entryID)
        }
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@MainActor
final class LogsViewModel: ObservableObject {
    private let sessionState: SessionState
    private var cancellables = Set<AnyCancellable>()

    init(sessionState: SessionState) {
        self.sessionState = sessionState
        sessionState.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var logs: [LogEntry] {
        sessionState.logs
    }

    func clearLogs() {
        sessionState.clearLogs()
    }

    func copyLogEntry(_ entry: LogEntry) {
        let text = "\(MainView.formatter.string(from: entry.timestamp)) \(entry.level.rawValue) \(entry.message)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
