import ApplicationServices
import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    struct ResolvedPromptSelection {
        let prompt: PromptConfig
        let isForActiveApp: Bool
    }

    private static let apiKeyKey = "VibeScribe.ApiKey"
    private static let deepgramLanguageKey = "VibeScribe.DeepgramLanguage"
    private static let historyLimitKey = "VibeScribe.HistoryLimit"
    private static let shortcutsKey = "VibeScribe.Shortcuts"
    private static let openRouterApiKeyKey = "VibeScribe.OpenRouterApiKey"
    private static let openRouterModelKey = "VibeScribe.OpenRouterModel"
    private static let promptsKey = "VibeScribe.Prompts"
    private static let legacyEnhancementPromptsKey = "VibeScribe.EnhancementPrompts"
    private static let escToCancelRecordingKey = "VibeScribe.EscToCancelRecording"
    private static let playSoundEffectsKey = "VibeScribe.PlaySoundEffects"
    private static let muteMediaDuringRecordingKey = "VibeScribe.MuteMediaDuringRecording"
    private static let restoreClipboardAfterPasteKey = "VibeScribe.RestoreClipboardAfterPaste"
    private static let overlayPositionKey = "VibeScribe.OverlayPosition"
    private static let accessibilityPromptDelayNanoseconds: UInt64 = 500_000_000
    private static let maxLogEntries = 1_000

    @Published var recordingPhase: RecordingPhase = .idle
    @Published var appStatus: AppStatus = .idle
    @Published var lastTranscript = ""
    @Published var finalTranscript = ""
    @Published var logs: [LogEntry] = []
    @Published var transcriptHistory: [TranscriptHistoryEntry] = []
    @Published var overlayPulseID = UUID()
    @Published var overlayVisible = false
    @Published var overlayLabel = "Listening"
    @Published var overlayAppIcon: NSImage?
    @Published var audioLevel: CGFloat = 0
    @Published var microphonePermission: PermissionStatus = .notDetermined
    @Published var accessibilityPermission: PermissionStatus = .notDetermined
    @Published var selectedTab: SettingsTab = .general

    var isRecording: Bool {
        recordingPhase == .recording
    }

    var statusMessage: String {
        appStatus.message
    }

    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: Self.apiKeyKey)
        }
    }

    @Published var shortcuts: [ShortcutConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(shortcuts) {
                UserDefaults.standard.set(data, forKey: Self.shortcutsKey)
            }
        }
    }

    @Published var openRouterApiKey: String {
        didSet {
            UserDefaults.standard.set(openRouterApiKey, forKey: Self.openRouterApiKeyKey)
        }
    }

    @Published var openRouterModel: String {
        didSet {
            UserDefaults.standard.set(openRouterModel, forKey: Self.openRouterModelKey)
        }
    }

    @Published var prompts: [PromptConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(prompts) {
                UserDefaults.standard.set(data, forKey: Self.promptsKey)
            }
        }
    }

    var hasOpenRouterCredentials: Bool {
        !openRouterApiKey.trimmed.isEmpty && !openRouterModel.trimmed.isEmpty
    }

    @Published var escToCancelRecording: Bool {
        didSet {
            UserDefaults.standard.set(escToCancelRecording, forKey: Self.escToCancelRecordingKey)
        }
    }

    @Published var playSoundEffects: Bool {
        didSet {
            UserDefaults.standard.set(playSoundEffects, forKey: Self.playSoundEffectsKey)
        }
    }

    @Published var muteMediaDuringRecording: Bool {
        didSet {
            UserDefaults.standard.set(muteMediaDuringRecording, forKey: Self.muteMediaDuringRecordingKey)
        }
    }

    @Published var restoreClipboardAfterPaste: Bool {
        didSet {
            UserDefaults.standard.set(restoreClipboardAfterPaste, forKey: Self.restoreClipboardAfterPasteKey)
        }
    }

    @Published var overlayPosition: OverlayPosition {
        didSet {
            UserDefaults.standard.set(overlayPosition.rawValue, forKey: Self.overlayPositionKey)
        }
    }

    @Published var deepgramLanguage: DeepgramLanguage {
        didSet {
            UserDefaults.standard.set(deepgramLanguage.rawValue, forKey: Self.deepgramLanguageKey)
        }
    }

    @Published var historyLimit: HistoryLimit = .ten {
        didSet {
            UserDefaults.standard.set(historyLimit.rawValue, forKey: Self.historyLimitKey)
            applyHistoryLimit()
        }
    }

    init() {
        apiKey = UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? ""
        escToCancelRecording = (UserDefaults.standard.object(forKey: Self.escToCancelRecordingKey) as? Bool) ?? true
        playSoundEffects = (UserDefaults.standard.object(forKey: Self.playSoundEffectsKey) as? Bool) ?? false
        muteMediaDuringRecording = (UserDefaults.standard.object(forKey: Self.muteMediaDuringRecordingKey) as? Bool) ?? false
        restoreClipboardAfterPaste = (UserDefaults.standard.object(forKey: Self.restoreClipboardAfterPasteKey) as? Bool) ?? false
        let savedPosition = UserDefaults.standard.string(forKey: Self.overlayPositionKey)
        overlayPosition = savedPosition.flatMap(OverlayPosition.init(rawValue:)) ?? .top
        let savedLanguage = UserDefaults.standard.string(forKey: Self.deepgramLanguageKey)
        deepgramLanguage = savedLanguage.flatMap(DeepgramLanguage.init(rawValue:)) ?? .automatic
        let savedLimit = UserDefaults.standard.integer(forKey: Self.historyLimitKey)
        historyLimit = HistoryLimit(rawValue: savedLimit) ?? .ten

        if let data = UserDefaults.standard.data(forKey: Self.shortcutsKey),
           let decoded = try? JSONDecoder().decode([ShortcutConfig].self, from: data),
           !decoded.isEmpty {
            shortcuts = decoded
        } else {
            shortcuts = [ShortcutConfig.makeDefault()]
        }

        openRouterApiKey = UserDefaults.standard.string(forKey: Self.openRouterApiKeyKey) ?? ""
        openRouterModel = UserDefaults.standard.string(forKey: Self.openRouterModelKey) ?? ""

        if let data = UserDefaults.standard.data(forKey: Self.promptsKey),
           let decoded = try? JSONDecoder().decode([PromptConfig].self, from: data) {
            prompts = decoded
        } else {
            prompts = []
            migrateLegacyEnhancementPrompts()
        }

        refreshPermissions()
    }

    func resetTranscript() {
        lastTranscript = ""
        finalTranscript = ""
        transcriptSegments.removeAll()
    }

    func handleTranscript(_ text: String, isFinal: Bool) {
        lastTranscript = text
        guard isFinal else { return }
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        if transcriptSegments.last != trimmed {
            transcriptSegments.append(trimmed)
            finalTranscript = transcriptSegments.joined(separator: " ")
        }
    }

    func finalizeLatestInterimTranscript() {
        let trimmed = lastTranscript.trimmed
        guard !trimmed.isEmpty else { return }
        if transcriptSegments.last != trimmed {
            transcriptSegments.append(trimmed)
            finalTranscript = transcriptSegments.joined(separator: " ")
        }
    }

    func addLog(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(timestamp: Date(), level: level, message: message))
        if logs.count > Self.maxLogEntries {
            logs.removeFirst(logs.count - Self.maxLogEntries)
        }
    }

    func addTranscriptToHistory(
        _ text: String,
        enhancedText: String? = nil,
        transcriptionError: String? = nil,
        enhancementError: String? = nil,
        promptName: String? = nil,
        usedActiveAppPrompt: Bool = false
    ) {
        guard historyLimit != .none else { return }
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: text,
            enhancedText: enhancedText,
            transcriptionError: transcriptionError,
            enhancementError: enhancementError,
            promptName: promptName,
            usedActiveAppPrompt: usedActiveAppPrompt
        )
        transcriptHistory.insert(entry, at: 0)
        applyHistoryLimit()
    }

    func addTranscriptionFailureToHistory(reason: String, partialText: String = "") {
        addTranscriptToHistory(
            partialText,
            transcriptionError: reason
        )
    }

    private func applyHistoryLimit() {
        let max = historyLimit.rawValue
        if max == 0 {
            transcriptHistory.removeAll()
        } else if transcriptHistory.count > max {
            transcriptHistory.removeLast(transcriptHistory.count - max)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func deletePrompt(id: UUID) {
        prompts.removeAll { $0.id == id }
        for i in shortcuts.indices where shortcuts[i].promptID == id {
            shortcuts[i].promptID = nil
        }
        for i in shortcuts.indices {
            shortcuts[i].appPromptOverrides.removeAll { $0.promptID == id }
        }
    }

    func promptContent(forShortcutID shortcutID: UUID, activeAppBundleIdentifier: String? = nil) -> String? {
        resolvedPromptSelection(forShortcutID: shortcutID, activeAppBundleIdentifier: activeAppBundleIdentifier)?.prompt.content
    }

    func resolvedPrompt(forShortcutID shortcutID: UUID, activeAppBundleIdentifier: String? = nil) -> PromptConfig? {
        resolvedPromptSelection(forShortcutID: shortcutID, activeAppBundleIdentifier: activeAppBundleIdentifier)?.prompt
    }

    func resolvedEnhancementPrompt(
        forShortcutID shortcutID: UUID,
        activeAppBundleIdentifier: String? = nil
    ) -> EnhancementPromptContext? {
        guard let selection = resolvedPromptSelection(
            forShortcutID: shortcutID,
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
        activeAppBundleIdentifier: String? = nil
    ) -> ResolvedPromptSelection? {
        guard let shortcut = shortcuts.first(where: { $0.id == shortcutID }) else {
            return nil
        }

        if let normalizedBundleIdentifier = AppPromptOverride.normalizeBundleIdentifier(activeAppBundleIdentifier),
           let overridePromptID = shortcut.appPromptOverrides.first(where: {
               $0.normalizedAppBundleIdentifier == normalizedBundleIdentifier
           })?.promptID,
           let prompt = prompts.first(where: { $0.id == overridePromptID }) {
            return ResolvedPromptSelection(prompt: prompt, isForActiveApp: true)
        }

        if let promptID = shortcut.promptID,
           let prompt = prompts.first(where: { $0.id == promptID }) {
            return ResolvedPromptSelection(prompt: prompt, isForActiveApp: false)
        }

        return nil
    }

    func upsertAppPromptOverride(
        shortcutID: UUID,
        appBundleIdentifier: String,
        appDisplayName: String,
        promptID: UUID? = nil
    ) {
        guard let normalizedBundleIdentifier = AppPromptOverride.normalizeBundleIdentifier(appBundleIdentifier),
              let shortcutIndex = shortcuts.firstIndex(where: { $0.id == shortcutID }) else {
            return
        }

        let resolvedPromptID = promptID ?? shortcuts[shortcutIndex].promptID ?? prompts.first?.id
        guard let resolvedPromptID else { return }

        let cleanedDisplayName = appDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanedDisplayName.isEmpty ? appBundleIdentifier : cleanedDisplayName

        if let overrideIndex = shortcuts[shortcutIndex].appPromptOverrides.firstIndex(where: {
            $0.normalizedAppBundleIdentifier == normalizedBundleIdentifier
        }) {
            shortcuts[shortcutIndex].appPromptOverrides[overrideIndex].appBundleIdentifier = normalizedBundleIdentifier
            shortcuts[shortcutIndex].appPromptOverrides[overrideIndex].appDisplayName = displayName
            shortcuts[shortcutIndex].appPromptOverrides[overrideIndex].promptID = resolvedPromptID
        } else {
            shortcuts[shortcutIndex].appPromptOverrides.append(
                AppPromptOverride(
                    appBundleIdentifier: normalizedBundleIdentifier,
                    appDisplayName: displayName,
                    promptID: resolvedPromptID
                )
            )
        }

        shortcuts[shortcutIndex].appPromptOverrides.sort {
            let nameOrder = $0.appDisplayName.localizedCaseInsensitiveCompare($1.appDisplayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return $0.appBundleIdentifier.localizedCaseInsensitiveCompare($1.appBundleIdentifier) == .orderedAscending
        }
    }

    private var transcriptSegments: [String] = []

    private func migrateLegacyEnhancementPrompts() {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyEnhancementPromptsKey),
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

        UserDefaults.standard.removeObject(forKey: Self.legacyEnhancementPromptsKey)
    }
}

struct TranscriptHistoryEntry: Identifiable {
    static let emptyTranscriptionMessage = "No speech was detected or no final transcript was returned."

    let id = UUID()
    let timestamp: Date
    let text: String
    let enhancedText: String?
    let transcriptionError: String?
    let enhancementError: String?
    let promptName: String?
    let usedActiveAppPrompt: Bool

    init(
        timestamp: Date,
        text: String,
        enhancedText: String? = nil,
        transcriptionError: String? = nil,
        enhancementError: String? = nil,
        promptName: String? = nil,
        usedActiveAppPrompt: Bool = false
    ) {
        self.timestamp = timestamp
        self.text = text
        self.enhancedText = enhancedText
        self.transcriptionError = transcriptionError
        self.enhancementError = enhancementError
        self.promptName = promptName
        self.usedActiveAppPrompt = usedActiveAppPrompt
    }

    var displayText: String {
        let source = (enhancedText ?? text).trimmed
        if source.isEmpty {
            if let transcriptionError {
                return "Transcription failed: \(transcriptionError)"
            }
            if let enhancementError {
                return "Enhancement failed: \(enhancementError)"
            }
            return ""
        }
        let sentences = source.splitIntoSentences()
        if sentences.count <= 3 { return source }
        return sentences.prefix(3).joined() + "…"
    }

    var shouldShowTranscriptionWarningIcon: Bool {
        guard let transcriptionError else { return false }
        return !(text.trimmed.isEmpty && transcriptionError == Self.emptyTranscriptionMessage)
    }

    var promptSourceLabel: String {
        usedActiveAppPrompt ? "Active app" : "Default"
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case top, bottom

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

extension String {
    func splitIntoSentences() -> [String] {
        var sentences: [String] = []
        enumerateSubstrings(in: startIndex..., options: .bySentences) { _, range, _, _ in
            sentences.append(String(self[range]))
        }
        return sentences
    }

}

enum PermissionStatus: String {
    case notDetermined = "Not requested"
    case denied = "Not granted"
    case authorized = "Granted"

    var isGranted: Bool {
        self == .authorized
    }

    var color: Color {
        switch self {
        case .authorized: .green
        case .denied: .orange
        case .notDetermined: .gray
        }
    }
}

extension AppState {
    func refreshPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .authorized
        case .denied, .restricted:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .denied
        }

        accessibilityPermission = AXIsProcessTrusted() ? .authorized : .denied
    }

    func requestMicrophonePermission(completion: (@Sendable () -> Void)? = nil) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
                completion?()
            }
        }
    }

    func requestAccessibilityPermission() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Self.accessibilityPromptDelayNanoseconds)
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            self.refreshPermissions()
        }
    }

    func requestInitialPermissionsIfNeeded() {
        refreshPermissions()
        if microphonePermission == .notDetermined {
            requestMicrophonePermission { [weak self] in
                Task { @MainActor in
                    self?.requestAccessibilityPermissionIfNeeded()
                }
            }
            return
        }

        requestAccessibilityPermissionIfNeeded()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        refreshPermissions()
        if accessibilityPermission != .authorized {
            requestAccessibilityPermission()
        }
    }
}
