import Foundation
import AppKit
import AVFoundation

struct ActiveApplicationContext {
    let bundleIdentifier: String?
    let icon: NSImage?
}

struct EnhancementPromptContext: Equatable {
    let name: String
    let content: String
    let isForActiveApp: Bool
}

struct RecordingFinalization {
    let enhancementPrompt: EnhancementPromptContext?
    let transcriptionError: String?
}

@MainActor
final class RecordingRuntime {
    private let audioCapture: AudioCapturePort
    private let deepgram: DeepgramPort
    private let scheduler: SchedulerPort
    private let clock: ClockPort

    private let activeApplicationProvider: () -> ActiveApplicationContext?
    private let audioInputSelectionProvider: () -> ResolvedAudioInputSelection
    private let languageProvider: () -> DeepgramLanguage
    private let apiKeyProvider: () -> String
    private let resolvedEnhancementPromptProvider: (UUID?, String?) -> EnhancementPromptContext?
    private let playSoundEffectsEnabledProvider: () -> Bool
    private let muteDuringRecordingProvider: () -> Bool
    private let soundPort: SoundPort

    private let stopDelay: TimeInterval
    private let reconnectDelay: TimeInterval
    private let finalizeWatchdogTimeout: TimeInterval
    private let maxReconnectAttempts: Int

    private var stopTask: CancellableTask?
    private var reconnectTask: CancellableTask?
    private var finalizeWatchdogTask: CancellableTask?

    private(set) var phase: RecordingPhase = .idle {
        didSet { onPhaseChanged?(phase) }
    }

    private(set) var ownership: RecordingOwnership? {
        didSet { onOwnershipChanged?(ownership) }
    }

    private var currentRecordingFormat: AudioStreamFormat?
    private var currentActiveApplication: ActiveApplicationContext?
    private var pendingTranscriptionError: String?
    private var pendingEnhancementPrompt: EnhancementPromptContext?
    private var deepgramReconnectAttempt = 0
    private var hasPlayedTranscriptionFailureSound = false
    private var didFinalizeCurrentSession = false

    var onStatus: ((AppStatus) -> Void)?
    var onLog: ((String, LogLevel) -> Void)?
    var onPhaseChanged: ((RecordingPhase) -> Void)?
    var onOwnershipChanged: ((RecordingOwnership?) -> Void)?
    var onOverlayUpdate: ((Bool, String, NSImage?) -> Void)?
    var onAudioLevel: ((CGFloat) -> Void)?
    var onTranscript: ((String, Bool) -> Void)?
    var onWillStartRecording: (() -> Void)?
    var onFinalizeLatestInterim: (() -> Void)?
    var onFinalizeRequested: ((RecordingFinalization) -> Void)?
    var onRequestOpenSettings: (() -> Void)?
    var onMuteForRecording: (() -> Void)?
    var onRestoreMute: (() -> Void)?

    init(
        audioCapture: AudioCapturePort,
        deepgram: DeepgramPort,
        scheduler: SchedulerPort,
        clock: ClockPort,
        activeApplicationProvider: @escaping () -> ActiveApplicationContext?,
        audioInputSelectionProvider: @escaping () -> ResolvedAudioInputSelection,
        languageProvider: @escaping () -> DeepgramLanguage,
        apiKeyProvider: @escaping () -> String,
        resolvedEnhancementPromptProvider: @escaping (UUID?, String?) -> EnhancementPromptContext?,
        playSoundEffectsEnabledProvider: @escaping () -> Bool,
        muteDuringRecordingProvider: @escaping () -> Bool,
        soundPort: SoundPort,
        stopDelay: TimeInterval = 0.2,
        reconnectDelay: TimeInterval = 0.4,
        finalizeWatchdogTimeout: TimeInterval = 1.2,
        maxReconnectAttempts: Int = DeepgramReconnectPolicy.maxAttempts
    ) {
        self.audioCapture = audioCapture
        self.deepgram = deepgram
        self.scheduler = scheduler
        self.clock = clock
        self.activeApplicationProvider = activeApplicationProvider
        self.audioInputSelectionProvider = audioInputSelectionProvider
        self.languageProvider = languageProvider
        self.apiKeyProvider = apiKeyProvider
        self.resolvedEnhancementPromptProvider = resolvedEnhancementPromptProvider
        self.playSoundEffectsEnabledProvider = playSoundEffectsEnabledProvider
        self.muteDuringRecordingProvider = muteDuringRecordingProvider
        self.soundPort = soundPort
        self.stopDelay = stopDelay
        self.reconnectDelay = reconnectDelay
        self.finalizeWatchdogTimeout = finalizeWatchdogTimeout
        self.maxReconnectAttempts = maxReconnectAttempts

        self.audioCapture.onConfigurationChanged = { [weak self] in
            Task { @MainActor in
                self?.handleAudioInputConfigurationChanged()
            }
        }
        self.deepgram.onTranscriptEvent = { [weak self] text, isFinal in
            Task { @MainActor in
                self?.handleTranscriptEvent(text, isFinal: isFinal)
            }
        }
        self.deepgram.onLog = { [weak self] message, level in
            Task { @MainActor in
                self?.onLog?(message, level)
            }
        }
        self.deepgram.onTranscriptionError = { [weak self] message in
            Task { @MainActor in
                self?.handleTranscriptionError(message)
            }
        }
        self.deepgram.onConnectionDropped = { [weak self] reason in
            Task { @MainActor in
                self?.handleDeepgramConnectionDropped(reason: reason)
            }
        }
    }

    func handle(actions: [ShortcutAction]) {
        for action in actions {
            handle(action: action)
        }
    }

    func handle(action: ShortcutAction) {
        switch action {
        case .start(let ownerShortcutID, let ownerMode, let latched):
            startRecording(ownerShortcutID: ownerShortcutID, ownerMode: ownerMode, isLatched: latched)
        case .stop:
            stopRecording()
        case .cancel:
            cancelRecording()
        case .scheduleStop:
            scheduleStopRecording()
        case .setLatched(let latched):
            guard var ownership else { return }
            ownership.isLatched = latched
            self.ownership = ownership
        case .noop:
            break
        }
    }

    func cancelFromEsc() {
        cancelRecording()
    }

    private func startRecording(ownerShortcutID: UUID, ownerMode: ShortcutMode, isLatched: Bool) {
        guard phase == .idle else { return }

        let apiKey = apiKeyProvider().trimmed
        guard !apiKey.isEmpty else {
            onStatus?(.missingAPIKey)
            onLog?("Missing API key. Open Settings to add one.", .warning)
            onRequestOpenSettings?()
            return
        }

        do {
            cancelPendingStop()
            cancelReconnect()
            cancelFinalizeWatchdog()

            pendingTranscriptionError = nil
            pendingEnhancementPrompt = nil
            currentActiveApplication = nil
            hasPlayedTranscriptionFailureSound = false
            deepgramReconnectAttempt = 0
            didFinalizeCurrentSession = false
            onWillStartRecording?()

            let activeApplication = activeApplicationProvider()
            currentActiveApplication = activeApplication
            pendingEnhancementPrompt = resolvedEnhancementPromptProvider(
                ownerShortcutID,
                activeApplication?.bundleIdentifier
            )

            let format = try audioCapture.start()
            currentRecordingFormat = format
            let resolvedAudioInput = audioInputSelectionProvider()
            let startedAt = clock.now()
            ownership = RecordingOwnership(
                ownerShortcutID: ownerShortcutID,
                ownerMode: ownerMode,
                isLatched: isLatched,
                recordingStartedAt: startedAt,
                sessionID: UUID()
            )

            phase = .recording
            onStatus?(.listening)
            onOverlayUpdate?(true, "Listening", overlayAppIcon)
            onLog?("Audio capture started (\(format.sampleRate) Hz, \(format.channels) ch).", .info)
            if resolvedAudioInput.isFallbackToSystemDefault {
                onLog?("Input: \(resolvedAudioInput.displayName). Saved microphone unavailable, using fallback.", .warning)
            } else {
                onLog?("Input: \(resolvedAudioInput.displayName).", .info)
            }
            deepgram.connect(apiKey: apiKey, format: format, language: languageProvider())

            audioCapture.onBuffer = { [weak self] buffer in
                guard let self else { return }
                self.deepgram.sendAudio(buffer: buffer)
                let level = rmsLevel(from: buffer)
                Task { @MainActor [weak self] in
                    self?.onAudioLevel?(level)
                }
            }

            if muteDuringRecordingProvider() {
                onMuteForRecording?()
            }
            playSound("Tink")
            onLog?("Language: \(languageProvider().displayName) (\(languageProvider().deepgramCode)).", .info)
            onLog?("Listening started.", .info)
        } catch {
            phase = .idle
            ownership = nil
            currentActiveApplication = nil
            pendingEnhancementPrompt = nil
            onStatus?(.failedToStartAudioCapture(error.localizedDescription))
            onLog?("Failed to start audio capture: \(error.localizedDescription)", .error)
        }
    }

    private func stopRecording() {
        guard phase == .recording else { return }

        cancelPendingStop()
        cancelReconnect()

        audioCapture.stop()
        phase = .finalizing
        onAudioLevel?(0)
        onStatus?(.finalizing)
        onRestoreMute?()

        if pendingEnhancementPrompt != nil {
            onOverlayUpdate?(true, "Enhancing", overlayAppIcon)
        } else {
            onOverlayUpdate?(true, "Listening", nil)
        }

        didFinalizeCurrentSession = false
        startFinalizeWatchdog()

        deepgram.closeStream { [weak self] in
            Task { @MainActor in
                self?.finalizeIfNeeded()
            }
        }
    }

    private func finalizeIfNeeded() {
        guard phase == .finalizing else { return }
        guard !didFinalizeCurrentSession else { return }

        didFinalizeCurrentSession = true
        cancelFinalizeWatchdog()

        let finalization = RecordingFinalization(
            enhancementPrompt: pendingEnhancementPrompt,
            transcriptionError: pendingTranscriptionError
        )

        finishActiveSession(
            disconnectDeepgram: true,
            clearPendingTranscriptionError: false,
            hideOverlay: false
        )
        onFinalizeRequested?(finalization)
    }

    private func startFinalizeWatchdog() {
        cancelFinalizeWatchdog()
        finalizeWatchdogTask = scheduler.schedule(after: finalizeWatchdogTimeout) { [weak self] in
            Task { @MainActor in
                self?.finalizeIfNeeded()
            }
        }
    }

    private func cancelFinalizeWatchdog() {
        finalizeWatchdogTask?.cancel()
        finalizeWatchdogTask = nil
    }

    private func handleTranscriptEvent(_ text: String, isFinal: Bool) {
        let wasRecovering = deepgramReconnectAttempt > 0 || reconnectTask != nil
        if wasRecovering {
            cancelReconnect()
            deepgramReconnectAttempt = 0
            if phase == .recording {
                onStatus?(.listening)
            }
            if pendingTranscriptionError != nil {
                pendingTranscriptionError = nil
                onLog?("Deepgram connection recovered. Transcription resumed.", .info)
            }
        }

        onTranscript?(text, isFinal)
    }

    private func handleTranscriptionError(_ message: String) {
        let isFirstErrorInSession = pendingTranscriptionError == nil
        pendingTranscriptionError = message
        if phase != .idle {
            onStatus?(.transcriptionIssueDetected)
        }
        if isFirstErrorInSession,
           phase != .idle,
           !hasPlayedTranscriptionFailureSound {
            playErrorSound(force: true)
            hasPlayedTranscriptionFailureSound = true
        }
    }

    private func handleDeepgramConnectionDropped(reason: String) {
        guard phase == .recording else { return }
        guard currentRecordingFormat != nil else { return }
        guard reconnectTask == nil else { return }

        onFinalizeLatestInterim?()

        if !DeepgramReconnectPolicy.shouldRetry(currentAttempt: deepgramReconnectAttempt) {
            onStatus?(.connectionLostReleaseToFinalize)
            onLog?(
                "Deepgram reconnect limit reached (\(maxReconnectAttempts) attempts). Last error: \(reason)",
                .error
            )
            return
        }

        deepgramReconnectAttempt += 1
        let attempt = deepgramReconnectAttempt
        let delayText = String(format: "%.1f", reconnectDelay)
        onStatus?(.connectionRecovering)
        onLog?(
            "Deepgram connection dropped. Reconnecting in \(delayText)s (attempt \(attempt)/\(maxReconnectAttempts)).",
            .warning
        )

        reconnectTask = scheduler.schedule(after: reconnectDelay) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.reconnectTask = nil
                guard self.phase == .recording else { return }
                guard let format = self.currentRecordingFormat else { return }
                let apiKey = self.apiKeyProvider().trimmed
                guard !apiKey.isEmpty else { return }

                self.onLog?("Attempting Deepgram reconnect (\(attempt)/\(self.maxReconnectAttempts)).", .warning)
                self.deepgram.connect(apiKey: apiKey, format: format, language: self.languageProvider())
            }
        }
    }

    private func handleAudioInputConfigurationChanged() {
        onLog?("Audio input changed. Capture engine reset.", .warning)
        guard phase != .idle else {
            onStatus?(.audioInputChangedReady)
            return
        }

        finishActiveSession(disconnectDeepgram: true, clearPendingTranscriptionError: true, hideOverlay: true)
        onStatus?(.inputChangedReady)
        onLog?("Recording stopped because the input device changed.", .warning)
    }

    private func cancelRecording() {
        guard phase != .idle else { return }

        finishActiveSession(disconnectDeepgram: true, clearPendingTranscriptionError: true, hideOverlay: true)
        playSound("Pop")
        onStatus?(.cancelled)
        onLog?("Recording cancelled.", .info)
    }

    private func scheduleStopRecording() {
        cancelPendingStop()
        stopTask = scheduler.schedule(after: stopDelay) { [weak self] in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }

    private func cancelPendingStop() {
        stopTask?.cancel()
        stopTask = nil
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func finishActiveSession(
        disconnectDeepgram: Bool,
        clearPendingTranscriptionError: Bool,
        hideOverlay: Bool
    ) {
        cancelPendingStop()
        cancelReconnect()
        cancelFinalizeWatchdog()
        audioCapture.stop()

        if disconnectDeepgram {
            deepgram.disconnect()
        }

        phase = .idle
        ownership = nil
        currentRecordingFormat = nil
        currentActiveApplication = nil
        pendingEnhancementPrompt = nil
        deepgramReconnectAttempt = 0
        didFinalizeCurrentSession = false
        onRestoreMute?()
        onAudioLevel?(0)

        if hideOverlay {
            onOverlayUpdate?(false, "Listening", nil)
        }

        if clearPendingTranscriptionError {
            pendingTranscriptionError = nil
            hasPlayedTranscriptionFailureSound = false
        }
    }

    private func playSound(_ name: String) {
        guard playSoundEffectsEnabledProvider() else { return }
        soundPort.play(named: name)
    }

    private func playErrorSound(force: Bool = false) {
        guard force || playSoundEffectsEnabledProvider() else { return }
        soundPort.play(named: "Basso")
    }

    private var overlayAppIcon: NSImage? {
        guard pendingEnhancementPrompt?.isForActiveApp == true else { return nil }
        return currentActiveApplication?.icon
    }
}

private func rmsLevel(from buffer: AVAudioPCMBuffer) -> CGFloat {
    guard let channelData = buffer.floatChannelData else { return 0 }
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return 0 }
    let samples = channelData[0]
    var sum: Float = 0
    for i in 0..<frameLength {
        let s = samples[i]
        sum += s * s
    }
    let rms = sqrt(sum / Float(frameLength))
    return CGFloat(min(1, sqrt(rms) * 3.5))
}
