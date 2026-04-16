import AppKit
import Combine
import Foundation

@MainActor
final class RuntimeCoordinator {
    private let settingsStore: SettingsStore
    private let sessionState: SessionState
    private let permissionService: PermissionService
    private let promptRoutingService: PromptRoutingService
    private let windowCoordinator: WindowCoordinator
    private let soundPort: SoundPort
    private let systemMuteController: SystemMuteController
    private let rawRecordingStore: RawRecordingStore

    private let shortcutRuntime: ShortcutRuntime
    private let recordingRuntime: RecordingRuntime
    private let pasteRuntime: PasteRuntime

    private var pasteTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore,
        sessionState: SessionState,
        permissionService: PermissionService,
        promptRoutingService: PromptRoutingService,
        windowCoordinator: WindowCoordinator,
        rawRecordingStore: RawRecordingStore,
        schedulerPort: SchedulerPort,
        clockPort: ClockPort,
        soundPort: SoundPort,
        pasteboardPort: PasteboardPort,
        pasteVerificationPort: PasteVerificationPort,
        audioCapturePort: AudioCapturePort,
        deepgramPort: DeepgramPort,
        eventMonitorPort: EventMonitorPort,
        activeApplicationProvider: @escaping () -> ActiveApplicationContext?
    ) {
        self.settingsStore = settingsStore
        self.sessionState = sessionState
        self.permissionService = permissionService
        self.promptRoutingService = promptRoutingService
        self.windowCoordinator = windowCoordinator
        self.soundPort = soundPort
        self.rawRecordingStore = rawRecordingStore
        self.systemMuteController = SystemMuteController { [weak sessionState] message, level in
            sessionState?.addLog(message, level: level)
        }

        self.pasteRuntime = PasteRuntime(
            pasteboard: pasteboardPort,
            pasteVerification: pasteVerificationPort,
            scheduler: schedulerPort,
            enhancer: { transcript, prompt, apiKey, model in
                try await OpenRouterClient.enhance(
                    transcript: transcript,
                    prompt: prompt,
                    apiKey: apiKey,
                    model: model
                )
            }
        )

        self.recordingRuntime = RecordingRuntime(
            audioCapture: audioCapturePort,
            deepgram: deepgramPort,
            scheduler: schedulerPort,
            clock: clockPort,
            activeApplicationProvider: activeApplicationProvider,
            audioInputSelectionProvider: { [weak settingsStore] in
                AudioInputCatalog.resolvedSelection(settingsStore?.audioInputSelection ?? .systemDefault)
            },
            languageProvider: { [weak settingsStore] in
                settingsStore?.deepgramLanguage ?? .automatic
            },
            apiKeyProvider: { [weak settingsStore] in
                settingsStore?.apiKey ?? ""
            },
            resolvedEnhancementPromptProvider: { [weak settingsStore, weak promptRoutingService] shortcutID, activeAppBundleIdentifier in
                guard let settingsStore, let promptRoutingService, let shortcutID else { return nil }
                return promptRoutingService.resolvedEnhancementPrompt(
                    forShortcutID: shortcutID,
                    settings: settingsStore,
                    activeAppBundleIdentifier: activeAppBundleIdentifier
                )
            },
            playSoundEffectsEnabledProvider: { [weak settingsStore] in
                settingsStore?.playSoundEffects ?? false
            },
            muteDuringRecordingProvider: { [weak settingsStore] in
                settingsStore?.muteMediaDuringRecording ?? false
            },
            rawRecordingCaptureProvider: { [weak rawRecordingStore] format in
                rawRecordingStore?.makeCapture(format: format) ?? RawRecordingStore().makeCapture(format: format)
            },
            soundPort: soundPort
        )

        self.shortcutRuntime = ShortcutRuntime(
            eventMonitor: eventMonitorPort,
            clock: clockPort,
            clickHoldThreshold: 0.2
        )

        bindRuntimes()
        bindSettings()
    }

    var canCancelFromEsc: Bool {
        recordingRuntime.phase != .idle || pasteTask != nil
    }

    func start() {
        shortcutRuntime.configure(shortcuts: settingsStore.shortcuts)
        shortcutRuntime.start()
    }

    func stop() {
        shortcutRuntime.stop()
    }

    func cancelFromEsc() {
        if recordingRuntime.phase != .idle {
            recordingRuntime.cancelFromEsc()
            return
        }

        pasteTask?.cancel()
    }

    private func bindSettings() {
        settingsStore.$shortcuts
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] shortcuts in
                self?.shortcutRuntime.configure(shortcuts: shortcuts)
            }
            .store(in: &cancellables)

        settingsStore.$historyLimit
            .receive(on: RunLoop.main)
            .sink { [weak self] limit in
                self?.sessionState.applyHistoryLimit(limit)
            }
            .store(in: &cancellables)
    }

    private func bindRuntimes() {
        shortcutRuntime.phaseProvider = { [weak self] in
            self?.recordingRuntime.phase ?? .idle
        }
        shortcutRuntime.ownershipProvider = { [weak self] in
            self?.recordingRuntime.ownership
        }
        shortcutRuntime.onActions = { [weak self] actions in
            self?.handleShortcutActions(actions)
        }

        recordingRuntime.onWillStartRecording = { [weak self] in
            self?.sessionState.resetTranscript()
        }
        recordingRuntime.onStatus = { [weak self] status in
            self?.sessionState.appStatus = status
        }
        recordingRuntime.onLog = { [weak self] message, level in
            self?.sessionState.addLog(message, level: level)
        }
        recordingRuntime.onPhaseChanged = { [weak self] phase in
            self?.sessionState.recordingPhase = phase
        }
        recordingRuntime.onOverlayUpdate = { [weak self] visible, label, appIcon in
            guard let self else { return }
            if visible {
                self.windowCoordinator.showOverlay(label: label, appIcon: appIcon)
            } else {
                self.windowCoordinator.hideOverlay()
            }
        }
        recordingRuntime.onAudioLevel = { [weak self] level in
            self?.sessionState.audioLevel = level
        }
        recordingRuntime.onTranscript = { [weak self] text, isFinal in
            self?.sessionState.handleTranscript(text, isFinal: isFinal)
        }
        recordingRuntime.onFinalizeLatestInterim = { [weak self] in
            self?.sessionState.finalizeLatestInterimTranscript()
        }
        recordingRuntime.onRequestOpenSettings = { [weak self] in
            self?.windowCoordinator.showMain(tab: .general)
        }
        recordingRuntime.onMuteForRecording = { [weak self] in
            self?.systemMuteController.muteForRecording()
        }
        recordingRuntime.onRestoreMute = { [weak self] in
            self?.systemMuteController.restoreMute()
        }
        recordingRuntime.onFinalizeRequested = { [weak self] finalization in
            guard let self else { return }
            self.pasteTask?.cancel()
            self.pasteTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.pasteTask = nil }
                await self.pasteRuntime.process(
                    session: FinalizedTranscriptSession(
                        finalTranscript: self.sessionState.finalTranscript,
                        lastTranscript: self.sessionState.lastTranscript,
                        enhancementPrompt: finalization.enhancementPrompt,
                        transcriptionError: finalization.transcriptionError,
                        rawRecordingFileURL: finalization.rawRecordingFileURL,
                        transcriptionLanguage: finalization.transcriptionLanguage
                    ),
                    settings: PasteRuntimeSettings(
                        openRouterApiKey: self.settingsStore.openRouterApiKey,
                        openRouterModel: self.settingsStore.openRouterModel,
                        playSoundEffects: self.settingsStore.playSoundEffects,
                        restoreClipboardAfterPaste: self.settingsStore.restoreClipboardAfterPaste
                    )
                )
            }
        }

        pasteRuntime.onEvent = { [weak self] event in
            self?.handlePasteRuntimeEvent(event)
        }
    }

    private func handleShortcutActions(_ actions: [ShortcutAction]) {
        for action in actions {
            if shouldRequestMicrophonePermission(for: action) {
                requestMicrophonePermissionForRecording()
                continue
            }

            recordingRuntime.handle(action: action)
        }
    }

    private func shouldRequestMicrophonePermission(for action: ShortcutAction) -> Bool {
        guard case .start = action else { return false }
        permissionService.refreshPermissions()
        return permissionService.microphonePermission != .authorized
    }

    private func requestMicrophonePermissionForRecording() {
        sessionState.appStatus = .microphonePermissionRequired
        sessionState.addLog("Microphone access is required before Talkie can start recording.", level: .warning)
        windowCoordinator.showMain(tab: .general)
        permissionService.requestMicrophonePermission()
    }

    private func handlePasteRuntimeEvent(_ event: PasteRuntimeEvent) {
        switch event {
        case .status(let status):
            sessionState.appStatus = status
        case .log(let message, let level):
            sessionState.addLog(message, level: level)
        case .historyEntry(let entry):
            sessionState.storeTranscriptHistoryEntry(entry, limit: settingsStore.historyLimit)
        case .hideOverlay:
            windowCoordinator.hideOverlay()
        case .playSound(let name):
            soundPort.play(named: name)
        }
    }
}
