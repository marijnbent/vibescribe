import AppKit
import Combine
import Foundation

@MainActor
final class RuntimeCoordinator {
    private let settingsStore: SettingsStore
    private let sessionState: SessionState
    private let promptRoutingService: PromptRoutingService
    private let windowCoordinator: WindowCoordinator
    private let soundPort: SoundPort
    private let systemMuteController: SystemMuteController

    private let shortcutRuntime: ShortcutRuntime
    private let recordingRuntime: RecordingRuntime
    private let pasteRuntime: PasteRuntime

    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore,
        sessionState: SessionState,
        promptRoutingService: PromptRoutingService,
        windowCoordinator: WindowCoordinator,
        schedulerPort: SchedulerPort,
        clockPort: ClockPort,
        soundPort: SoundPort,
        pasteboardPort: PasteboardPort,
        audioCapturePort: AudioCapturePort,
        deepgramPort: DeepgramPort,
        eventMonitorPort: EventMonitorPort,
        activeApplicationProvider: @escaping () -> ActiveApplicationContext?
    ) {
        self.settingsStore = settingsStore
        self.sessionState = sessionState
        self.promptRoutingService = promptRoutingService
        self.windowCoordinator = windowCoordinator
        self.soundPort = soundPort
        self.systemMuteController = SystemMuteController { [weak sessionState] message, level in
            sessionState?.addLog(message, level: level)
        }

        self.pasteRuntime = PasteRuntime(
            pasteboard: pasteboardPort,
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

    var isRecording: Bool {
        sessionState.isRecording
    }

    func start() {
        shortcutRuntime.configure(shortcuts: settingsStore.shortcuts)
        shortcutRuntime.start()
    }

    func stop() {
        shortcutRuntime.stop()
    }

    func cancelFromEsc() {
        recordingRuntime.cancelFromEsc()
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
            self?.recordingRuntime.handle(actions: actions)
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
            Task { @MainActor in
                await self.pasteRuntime.process(
                    session: FinalizedTranscriptSession(
                        finalTranscript: self.sessionState.finalTranscript,
                        lastTranscript: self.sessionState.lastTranscript,
                        enhancementPrompt: finalization.enhancementPrompt,
                        transcriptionError: finalization.transcriptionError
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
