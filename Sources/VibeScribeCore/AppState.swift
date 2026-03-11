import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let settingsStore: SettingsStore
    let sessionState: SessionState
    let permissionService: PermissionService
    let mainViewModel: MainViewModel
    let promptRoutingService: PromptRoutingService

    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore = SettingsStore(),
        sessionState: SessionState = SessionState(),
        permissionService: PermissionService = PermissionService(),
        mainViewModel: MainViewModel = MainViewModel(),
        promptRoutingService: PromptRoutingService = PromptRoutingService()
    ) {
        self.settingsStore = settingsStore
        self.sessionState = sessionState
        self.permissionService = permissionService
        self.mainViewModel = mainViewModel
        self.promptRoutingService = promptRoutingService

        bindChildren()
        sessionState.applyHistoryLimit(settingsStore.historyLimit)
    }

    private func bindChildren() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        sessionState.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        permissionService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        mainViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settingsStore.$historyLimit
            .sink { [weak sessionState] limit in
                sessionState?.applyHistoryLimit(limit)
            }
            .store(in: &cancellables)
    }

    var recordingPhase: RecordingPhase {
        get { sessionState.recordingPhase }
        set { sessionState.recordingPhase = newValue }
    }

    var appStatus: AppStatus {
        get { sessionState.appStatus }
        set { sessionState.appStatus = newValue }
    }

    var lastTranscript: String {
        get { sessionState.lastTranscript }
        set { sessionState.lastTranscript = newValue }
    }

    var finalTranscript: String {
        get { sessionState.finalTranscript }
        set { sessionState.finalTranscript = newValue }
    }

    var logs: [LogEntry] {
        get { sessionState.logs }
        _modify { yield &sessionState.logs }
        set { sessionState.logs = newValue }
    }

    var transcriptHistory: [TranscriptHistoryEntry] {
        get { sessionState.transcriptHistory }
        _modify { yield &sessionState.transcriptHistory }
        set { sessionState.transcriptHistory = newValue }
    }

    var overlayPulseID: UUID {
        get { sessionState.overlayPulseID }
        set { sessionState.overlayPulseID = newValue }
    }

    var overlayVisible: Bool {
        get { sessionState.overlayVisible }
        set { sessionState.overlayVisible = newValue }
    }

    var overlayLabel: String {
        get { sessionState.overlayLabel }
        set { sessionState.overlayLabel = newValue }
    }

    var overlayAppIcon: NSImage? {
        get { sessionState.overlayAppIcon }
        set { sessionState.overlayAppIcon = newValue }
    }

    var audioLevel: CGFloat {
        get { sessionState.audioLevel }
        set { sessionState.audioLevel = newValue }
    }

    var microphonePermission: PermissionStatus {
        get { permissionService.microphonePermission }
        set { permissionService.microphonePermission = newValue }
    }

    var accessibilityPermission: PermissionStatus {
        get { permissionService.accessibilityPermission }
        set { permissionService.accessibilityPermission = newValue }
    }

    var selectedTab: SettingsTab {
        get { mainViewModel.selectedTab }
        set { mainViewModel.selectedTab = newValue }
    }

    var isRecording: Bool {
        sessionState.isRecording
    }

    var statusMessage: String {
        sessionState.statusMessage
    }

    var apiKey: String {
        get { settingsStore.apiKey }
        set { settingsStore.apiKey = newValue }
    }

    var shortcuts: [ShortcutConfig] {
        get { settingsStore.shortcuts }
        _modify { yield &settingsStore.shortcuts }
        set { settingsStore.shortcuts = newValue }
    }

    var openRouterApiKey: String {
        get { settingsStore.openRouterApiKey }
        set { settingsStore.openRouterApiKey = newValue }
    }

    var openRouterModel: String {
        get { settingsStore.openRouterModel }
        set { settingsStore.openRouterModel = newValue }
    }

    var prompts: [PromptConfig] {
        get { settingsStore.prompts }
        _modify { yield &settingsStore.prompts }
        set { settingsStore.prompts = newValue }
    }

    var hasOpenRouterCredentials: Bool {
        settingsStore.hasOpenRouterCredentials
    }

    var escToCancelRecording: Bool {
        get { settingsStore.escToCancelRecording }
        set { settingsStore.escToCancelRecording = newValue }
    }

    var playSoundEffects: Bool {
        get { settingsStore.playSoundEffects }
        set { settingsStore.playSoundEffects = newValue }
    }

    var muteMediaDuringRecording: Bool {
        get { settingsStore.muteMediaDuringRecording }
        set { settingsStore.muteMediaDuringRecording = newValue }
    }

    var restoreClipboardAfterPaste: Bool {
        get { settingsStore.restoreClipboardAfterPaste }
        set { settingsStore.restoreClipboardAfterPaste = newValue }
    }

    var overlayPosition: OverlayPosition {
        get { settingsStore.overlayPosition }
        set { settingsStore.overlayPosition = newValue }
    }

    var audioInputSelection: AudioInputSelection {
        get { settingsStore.audioInputSelection }
        set { settingsStore.audioInputSelection = newValue }
    }

    var deepgramLanguage: DeepgramLanguage {
        get { settingsStore.deepgramLanguage }
        set { settingsStore.deepgramLanguage = newValue }
    }

    var starredDeepgramLanguages: [DeepgramLanguage] {
        get { settingsStore.starredDeepgramLanguages }
        set { settingsStore.starredDeepgramLanguages = newValue }
    }

    var historyLimit: HistoryLimit {
        get { settingsStore.historyLimit }
        set { settingsStore.historyLimit = newValue }
    }

    func resetTranscript() {
        sessionState.resetTranscript()
    }

    func handleTranscript(_ text: String, isFinal: Bool) {
        sessionState.handleTranscript(text, isFinal: isFinal)
    }

    func finalizeLatestInterimTranscript() {
        sessionState.finalizeLatestInterimTranscript()
    }

    func addLog(_ message: String, level: LogLevel = .info) {
        sessionState.addLog(message, level: level)
    }

    func addTranscriptToHistory(
        _ text: String,
        enhancedText: String? = nil,
        transcriptionError: String? = nil,
        enhancementError: String? = nil,
        promptName: String? = nil,
        usedActiveAppPrompt: Bool = false
    ) {
        sessionState.addTranscriptToHistory(
            text,
            enhancedText: enhancedText,
            transcriptionError: transcriptionError,
            enhancementError: enhancementError,
            promptName: promptName,
            usedActiveAppPrompt: usedActiveAppPrompt,
            limit: settingsStore.historyLimit
        )
    }

    func addTranscriptionFailureToHistory(reason: String, partialText: String = "") {
        sessionState.addTranscriptionFailureToHistory(
            reason: reason,
            partialText: partialText,
            limit: settingsStore.historyLimit
        )
    }

    func clearLogs() {
        sessionState.clearLogs()
    }

    func deletePrompt(id: UUID) {
        promptRoutingService.deletePrompt(id: id, settings: settingsStore)
    }

    func promptContent(forShortcutID shortcutID: UUID, activeAppBundleIdentifier: String? = nil) -> String? {
        promptRoutingService.promptContent(
            forShortcutID: shortcutID,
            settings: settingsStore,
            activeAppBundleIdentifier: activeAppBundleIdentifier
        )
    }

    func resolvedPrompt(forShortcutID shortcutID: UUID, activeAppBundleIdentifier: String? = nil) -> PromptConfig? {
        promptRoutingService.resolvedPrompt(
            forShortcutID: shortcutID,
            settings: settingsStore,
            activeAppBundleIdentifier: activeAppBundleIdentifier
        )
    }

    func resolvedEnhancementPrompt(
        forShortcutID shortcutID: UUID,
        activeAppBundleIdentifier: String? = nil
    ) -> EnhancementPromptContext? {
        promptRoutingService.resolvedEnhancementPrompt(
            forShortcutID: shortcutID,
            settings: settingsStore,
            activeAppBundleIdentifier: activeAppBundleIdentifier
        )
    }

    func resolvedPromptSelection(
        forShortcutID shortcutID: UUID,
        activeAppBundleIdentifier: String? = nil
    ) -> PromptRoutingService.ResolvedPromptSelection? {
        promptRoutingService.resolvedPromptSelection(
            forShortcutID: shortcutID,
            settings: settingsStore,
            activeAppBundleIdentifier: activeAppBundleIdentifier
        )
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

    func refreshPermissions() {
        permissionService.refreshPermissions()
    }

    func requestMicrophonePermission(completion: (@Sendable () -> Void)? = nil) {
        permissionService.requestMicrophonePermission(completion: completion)
    }

    func requestAccessibilityPermission() {
        permissionService.requestAccessibilityPermission()
    }

    func requestInitialPermissionsIfNeeded() {
        permissionService.requestInitialPermissionsIfNeeded()
    }
}
