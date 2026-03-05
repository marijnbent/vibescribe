import AppKit
import Carbon
import Combine
import CoreAudio
import SwiftUI

@MainActor
public final class VibeScribeApp: NSObject, NSApplicationDelegate {
    public static func main() {
        let app = NSApplication.shared
        let delegate = VibeScribeApp()
        app.delegate = delegate
        app.run()
    }

    private var appState: AppState!
    private var menuBarController: MenuBarController!
    private var mainWindowController: MainWindowController!
    private var overlayWindowController: OverlayWindowController!

    private var shortcutRuntime: ShortcutRuntime!
    private var recordingRuntime: RecordingRuntime!
    private var pasteRuntime: PasteRuntime!

    private let eventMonitorPort: EventMonitorPort = NSEventMonitorAdapter()
    private let schedulerPort: SchedulerPort = DispatchSchedulerAdapter()
    private let clockPort: ClockPort = SystemClockAdapter()
    private let soundPort: SoundPort = NSSoundAdapter()
    private let pasteboardPort: PasteboardPort = NSPasteboardAdapter()
    private let audioCapturePort: AudioCapturePort = AudioCaptureControllerAdapter()
    private let deepgramPort: DeepgramPort = DeepgramClientAdapter()

    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?
    private var savedMuteState: Bool?
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppMenuBuilder.build()

        appState = AppState()
        mainWindowController = MainWindowController(appState: appState)
        overlayWindowController = OverlayWindowController(appState: appState)

        configureRuntimes()
        configureMenuBar()
        configureShortcutBindings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        startEscMonitor()

        appState.requestInitialPermissionsIfNeeded()
        appState.addLog("VibeScribe launched.", level: .info)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        shortcutRuntime.stop()
        stopEscMonitor()
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        appState.refreshPermissions()
    }

    private func configureRuntimes() {
        recordingRuntime = RecordingRuntime(
            audioCapture: audioCapturePort,
            deepgram: deepgramPort,
            scheduler: schedulerPort,
            clock: clockPort,
            languageProvider: { [weak self] in
                self?.appState.deepgramLanguage ?? .automatic
            },
            apiKeyProvider: { [weak self] in
                self?.appState.apiKey ?? ""
            },
            hasEnhancementForShortcut: { [weak self] shortcutID in
                guard let self else { return false }
                guard let shortcutID else { return false }
                return self.appState.promptContent(forShortcutID: shortcutID) != nil
            },
            playSoundEffectsEnabledProvider: { [weak self] in
                self?.appState.playSoundEffects ?? false
            },
            muteDuringRecordingProvider: { [weak self] in
                self?.appState.muteMediaDuringRecording ?? false
            },
            soundPort: soundPort
        )

        pasteRuntime = PasteRuntime(
            appState: appState,
            pasteboard: pasteboardPort,
            soundPort: soundPort,
            scheduler: schedulerPort,
            enhancer: { transcript, prompt, apiKey, model in
                try await OpenRouterClient.enhance(
                    transcript: transcript,
                    prompt: prompt,
                    apiKey: apiKey,
                    model: model
                )
            },
            restoreClipboardAfterPaste: { [weak self] in
                self?.appState.restoreClipboardAfterPaste ?? false
            }
        )

        shortcutRuntime = ShortcutRuntime(
            eventMonitor: eventMonitorPort,
            clock: clockPort,
            clickHoldThreshold: 0.2
        )

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
            self?.appState.resetTranscript()
        }
        recordingRuntime.onStatus = { [weak self] status in
            self?.appState.appStatus = status
        }
        recordingRuntime.onLog = { [weak self] message, level in
            self?.appState.addLog(message, level: level)
        }
        recordingRuntime.onPhaseChanged = { [weak self] phase in
            self?.appState.recordingPhase = phase
        }
        recordingRuntime.onOverlayUpdate = { [weak self] visible, label in
            self?.setOverlay(visible: visible, label: label)
        }
        recordingRuntime.onAudioLevel = { [weak self] level in
            self?.appState.audioLevel = level
        }
        recordingRuntime.onTranscript = { [weak self] text, isFinal in
            self?.appState.handleTranscript(text, isFinal: isFinal)
        }
        recordingRuntime.onFinalizeLatestInterim = { [weak self] in
            self?.appState.finalizeLatestInterimTranscript()
        }
        recordingRuntime.onRequestOpenSettings = { [weak self] in
            self?.mainWindowController.show()
        }
        recordingRuntime.onMuteForRecording = { [weak self] in
            self?.muteForRecording()
        }
        recordingRuntime.onRestoreMute = { [weak self] in
            self?.restoreMute()
        }
        recordingRuntime.onFinalizeRequested = { [weak self] finalization in
            guard let self else { return }
            Task { @MainActor in
                await self.pasteRuntime.pasteFinalTranscript(
                    shortcutID: finalization.shortcutID,
                    transcriptionError: finalization.transcriptionError
                )
            }
        }

        pasteRuntime.onHideOverlay = { [weak self] in
            self?.setOverlay(visible: false, label: nil)
        }
    }

    private func configureShortcutBindings() {
        shortcutRuntime.configure(shortcuts: appState.shortcuts)
        shortcutRuntime.start()

        appState.$shortcuts
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] shortcuts in
                self?.shortcutRuntime.configure(shortcuts: shortcuts)
            }
            .store(in: &cancellables)
    }

    private func configureMenuBar() {
        menuBarController = MenuBarController(
            onOpenMain: { [weak self] in
                self?.appState.selectedTab = .general
                self?.mainWindowController.show()
            },
            onOpenHistory: { [weak self] in
                self?.appState.selectedTab = .history
                self?.mainWindowController.show()
            },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    private func setOverlay(visible: Bool, label: String?) {
        if let label {
            appState.overlayLabel = label
        }

        if visible {
            appState.overlayVisible = true
            overlayWindowController.show()
        } else {
            appState.overlayVisible = false
            overlayWindowController.hide()
        }
    }

    // MARK: - ESC Key Monitor

    private func startEscMonitor() {
        let escKeyCode = UInt16(kVK_Escape)

        escGlobalMonitor = eventMonitorPort.addGlobalMonitor(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escKeyCode else { return }
            Task { @MainActor in
                guard let self, self.appState.isRecording, self.appState.escToCancelRecording else { return }
                self.recordingRuntime.cancelFromEsc()
            }
        }

        escLocalMonitor = eventMonitorPort.addLocalMonitor(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escKeyCode else { return event }
            Task { @MainActor in
                guard let self, self.appState.isRecording, self.appState.escToCancelRecording else { return }
                self.recordingRuntime.cancelFromEsc()
            }
            return event
        }
    }

    private func stopEscMonitor() {
        if let monitor = escGlobalMonitor {
            eventMonitorPort.removeMonitor(monitor)
            escGlobalMonitor = nil
        }
        if let monitor = escLocalMonitor {
            eventMonitorPort.removeMonitor(monitor)
            escLocalMonitor = nil
        }
    }

    // MARK: - Media Mute Control

    private func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else { return nil }
        return deviceID
    }

    private func setSystemMute(_ mute: Bool) {
        guard let device = defaultOutputDevice() else {
            appState.addLog("Unable to set mute state: no default output device.", level: .warning)
            return
        }
        var value: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        if status != noErr {
            appState.addLog("Failed to set system mute=\(mute) (CoreAudio status \(status)).", level: .warning)
        }
    }

    private func isSystemMuted() -> Bool {
        guard let device = defaultOutputDevice() else {
            appState.addLog("Unable to read mute state: no default output device.", level: .warning)
            return false
        }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        if status != noErr {
            appState.addLog("Failed to read system mute state (CoreAudio status \(status)).", level: .warning)
            return false
        }
        return value != 0
    }

    private func muteForRecording() {
        savedMuteState = isSystemMuted()
        setSystemMute(true)
    }

    private func restoreMute() {
        guard let wasMuted = savedMuteState else { return }
        savedMuteState = nil
        setSystemMute(wasMuted)
    }
}
