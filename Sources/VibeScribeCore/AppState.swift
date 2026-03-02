import ApplicationServices
import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private static let apiKeyKey = "VibeScribe.ApiKey"
    private static let deepgramLanguageKey = "VibeScribe.DeepgramLanguage"
    private static let historyLimitKey = "VibeScribe.HistoryLimit"
    private static let shortcutsKey = "VibeScribe.Shortcuts"
    private static let openRouterApiKeyKey = "VibeScribe.OpenRouterApiKey"
    private static let openRouterModelKey = "VibeScribe.OpenRouterModel"
    private static let enhancementPromptsKey = "VibeScribe.EnhancementPrompts"
    private static let escToCancelRecordingKey = "VibeScribe.EscToCancelRecording"
    private static let playSoundEffectsKey = "VibeScribe.PlaySoundEffects"
    private static let pauseMediaDuringRecordingKey = "VibeScribe.PauseMediaDuringRecording"
    private static let accessibilityPromptDelayNanoseconds: UInt64 = 500_000_000

    @Published var isRecording = false
    @Published var statusMessage = "Idle"
    @Published var lastTranscript = ""
    @Published var finalTranscript = ""
    @Published var logs: [LogEntry] = []
    @Published var transcriptHistory: [TranscriptHistoryEntry] = []
    @Published var overlayPulseID = UUID()
    @Published var overlayVisible = false
    @Published var overlayLabel = "Listening"
    @Published var microphonePermission: PermissionStatus = .notDetermined
    @Published var accessibilityPermission: PermissionStatus = .notDetermined
    @Published var selectedTab: SettingsTab = .general

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

    @Published var enhancementPrompts: [UUID: String] {
        didSet {
            let stringKeyed = Dictionary(uniqueKeysWithValues: enhancementPrompts.map { ($0.key.uuidString, $0.value) })
            if let data = try? JSONEncoder().encode(stringKeyed) {
                UserDefaults.standard.set(data, forKey: Self.enhancementPromptsKey)
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

    @Published var pauseMediaDuringRecording: Bool {
        didSet {
            UserDefaults.standard.set(pauseMediaDuringRecording, forKey: Self.pauseMediaDuringRecordingKey)
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
        pauseMediaDuringRecording = (UserDefaults.standard.object(forKey: Self.pauseMediaDuringRecordingKey) as? Bool) ?? false
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

        if let data = UserDefaults.standard.data(forKey: Self.enhancementPromptsKey),
           let stringKeyed = try? JSONDecoder().decode([String: String].self, from: data) {
            var prompts: [UUID: String] = [:]
            for (key, value) in stringKeyed {
                if let uuid = UUID(uuidString: key) {
                    prompts[uuid] = value
                }
            }
            enhancementPrompts = prompts
        } else {
            enhancementPrompts = [:]
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

    func addLog(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(timestamp: Date(), level: level, message: message))
    }

    func addTranscriptToHistory(_ text: String, enhancedText: String? = nil) {
        guard historyLimit != .none else { return }
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: text, enhancedText: enhancedText)
        transcriptHistory.insert(entry, at: 0)
        applyHistoryLimit()
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

    private var transcriptSegments: [String] = []
}

struct TranscriptHistoryEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let enhancedText: String?

    init(timestamp: Date, text: String, enhancedText: String? = nil) {
        self.timestamp = timestamp
        self.text = text
        self.enhancedText = enhancedText
    }

    var displayText: String {
        let source = enhancedText ?? text
        let sentences = source.splitIntoSentences()
        if sentences.count <= 3 { return source }
        return sentences.prefix(3).joined() + "…"
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
