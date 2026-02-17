import ApplicationServices
import AVFoundation
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    private static let apiKeyKey = "VibeScrib.ApiKey"
    private static let accessibilityPromptedKey = "VibeScrib.AccessibilityPrompted"

    @Published var isRecording = false
    @Published var statusMessage = "Idle"
    @Published var lastTranscript = ""
    @Published var finalTranscript = ""
    @Published var logs: [LogEntry] = []
    @Published var overlayPulseID = UUID()
    @Published var microphonePermission: PermissionStatus = .notDetermined
    @Published var accessibilityPermission: PermissionStatus = .notDetermined

    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: Self.apiKeyKey)
        }
    }

    @Published var hotkey = Hotkey.pushToTalkDefault

    init() {
        apiKey = UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? ""
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

    func clearLogs() {
        logs.removeAll()
    }

    private var transcriptSegments: [String] = []
}

enum PermissionStatus: String {
    case notDetermined = "Not requested"
    case denied = "Not granted"
    case authorized = "Granted"

    var isGranted: Bool {
        self == .authorized
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

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
            }
        }
    }

    func requestAccessibilityPermission() {
        UserDefaults.standard.set(true, forKey: Self.accessibilityPromptedKey)
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        refreshPermissions()
    }

    func requestInitialPermissionsIfNeeded() {
        if microphonePermission == .notDetermined {
            requestMicrophonePermission()
        }

        if accessibilityPermission != .authorized
            && !UserDefaults.standard.bool(forKey: Self.accessibilityPromptedKey) {
            requestAccessibilityPermission()
        }
    }
}
