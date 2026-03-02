import AppKit
import ApplicationServices
import AVFoundation
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
    private var hotkeyListeners: [UUID: HotkeyListener] = [:]
    private var audioCapture: AudioCaptureController!
    private var deepgramClient: DeepgramClient!
    private var stopWorkItem: DispatchWorkItem?
    private var isLatchedRecording = false
    private var savedMuteState: Bool?
    private var activeShortcutID: UUID?
    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var recordingStartTime: TimeInterval = 0
    private let clickHoldThreshold: TimeInterval = 0.2
    private let stopDelay: TimeInterval = 0.2
    private let clipboardRestoreDelay: TimeInterval = 0.2

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppMenuBuilder.build()

        appState = AppState()
        audioCapture = AudioCaptureController()
        audioCapture.onConfigurationChanged = { [weak self] in
            self?.handleAudioInputConfigurationChanged()
        }
        deepgramClient = DeepgramClient(
            onTranscriptEvent: { [weak self] text, isFinal in
                Task { @MainActor in
                    self?.appState.handleTranscript(text, isFinal: isFinal)
                }
            },
            onLog: { [weak self] message, level in
                Task { @MainActor in
                    self?.appState.addLog(message, level: level)
                }
            }
        )

        mainWindowController = MainWindowController(appState: appState)
        overlayWindowController = OverlayWindowController(appState: appState)

        rebuildHotkeyListeners()
        appState.$shortcuts
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildHotkeyListeners()
            }
            .store(in: &cancellables)

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

    // MARK: - Hotkey Listener Management

    private func rebuildHotkeyListeners() {
        for listener in hotkeyListeners.values {
            listener.stop()
        }
        hotkeyListeners.removeAll()

        for shortcut in appState.shortcuts {
            let hotkey = Hotkey(shortcutKey: shortcut.key)
            let listener = HotkeyListener(hotkey: hotkey)
            let id = shortcut.id
            let mode = shortcut.mode

            listener.onKeyDown = { [weak self] in
                self?.handleKeyDown(shortcutID: id, mode: mode)
            }
            listener.onKeyUp = { [weak self] in
                self?.handleKeyUp(shortcutID: id, mode: mode)
            }
            listener.start()
            hotkeyListeners[id] = listener
        }
    }

    // MARK: - Mode-Based Key Handling

    private func handleKeyDown(shortcutID: UUID, mode: ShortcutMode) {
        switch mode {
        case .hold:
            handleHoldKeyDown(shortcutID: shortcutID)
        case .click:
            handleClickKeyDown(shortcutID: shortcutID)
        case .both:
            handleBothKeyDown(shortcutID: shortcutID)
        }
    }

    private func handleKeyUp(shortcutID: UUID, mode: ShortcutMode) {
        switch mode {
        case .hold:
            handleHoldKeyUp(shortcutID: shortcutID)
        case .click:
            break
        case .both:
            handleBothKeyUp(shortcutID: shortcutID)
        }
    }

    // MARK: Hold Mode

    private func handleHoldKeyDown(shortcutID: UUID) {
        guard !appState.isRecording else { return }
        activeShortcutID = shortcutID
        startRecording()
    }

    private func handleHoldKeyUp(shortcutID: UUID) {
        guard activeShortcutID == shortcutID else { return }
        let elapsed = CACurrentMediaTime() - recordingStartTime
        if elapsed < clickHoldThreshold {
            cancelRecording()
            return
        }
        scheduleStopRecording()
    }

    // MARK: Click Mode

    private func handleClickKeyDown(shortcutID: UUID) {
        if appState.isRecording && activeShortcutID == shortcutID {
            isLatchedRecording = false
            stopRecording()
            return
        }
        activeShortcutID = shortcutID
        isLatchedRecording = true
        startRecording()
    }

    // MARK: Both Mode (Hold + Click)

    private func handleBothKeyDown(shortcutID: UUID) {
        if isLatchedRecording && activeShortcutID == shortcutID {
            isLatchedRecording = false
            stopRecording()
            return
        }

        if !appState.isRecording {
            activeShortcutID = shortcutID
            cancelPendingStop()
            startRecording()
        }
    }

    private func handleBothKeyUp(shortcutID: UUID) {
        guard activeShortcutID == shortcutID else { return }
        if isLatchedRecording { return }
        guard appState.isRecording else { return }
        let elapsed = CACurrentMediaTime() - recordingStartTime
        if elapsed < clickHoldThreshold {
            isLatchedRecording = true
        } else {
            scheduleStopRecording()
        }
    }

    // MARK: - Audio Input Change

    private func handleAudioInputConfigurationChanged() {
        appState.addLog("Audio input changed. Capture engine reset.", level: .warning)
        guard appState.isRecording else {
            appState.statusMessage = "Audio input changed. Ready."
            return
        }

        cancelPendingStop()
        isLatchedRecording = false
        activeShortcutID = nil
        restoreMute()
        deepgramClient.disconnect()
        appState.isRecording = false
        appState.overlayVisible = false
        overlayWindowController.hide()
        appState.statusMessage = "Input changed. Ready."
        appState.addLog("Recording stopped because the input device changed.", level: .warning)
    }

    // MARK: - Recording

    private func startRecording() {
        guard !appState.isRecording else { return }

        let apiKey = appState.apiKey.trimmed
        guard !apiKey.isEmpty else {
            appState.statusMessage = "Add a Deepgram API key in Settings."
            appState.addLog("Missing API key. Open Settings to add one.", level: .warning)
            mainWindowController.show()
            return
        }

        do {
            appState.resetTranscript()
            let format = try audioCapture.start()
            appState.addLog("Audio capture started (\(format.sampleRate) Hz, \(format.channels) ch).", level: .info)
            deepgramClient.connect(apiKey: apiKey, format: format, language: appState.deepgramLanguage)

            audioCapture.onBuffer = { [weak self] buffer in
                self?.deepgramClient.sendAudio(buffer: buffer)
                let level = rmsLevel(from: buffer)
                Task { @MainActor in
                    self?.appState.audioLevel = level
                }
            }

            recordingStartTime = CACurrentMediaTime()
            appState.isRecording = true
            appState.overlayLabel = "Listening"
            appState.overlayVisible = true
            appState.statusMessage = "Listening..."
            overlayWindowController.show()
            playSound("Tink")
            if appState.muteMediaDuringRecording {
                muteForRecording()
            }
            appState.addLog("Language: \(appState.deepgramLanguage.displayName) (\(appState.deepgramLanguage.deepgramCode)).", level: .info)
            appState.addLog("Listening started.", level: .info)
        } catch {
            isLatchedRecording = false
            activeShortcutID = nil
            appState.statusMessage = "Failed to start audio capture: \(error.localizedDescription)"
            appState.addLog("Failed to start audio capture: \(error.localizedDescription)", level: .error)
        }
    }

    private func stopRecording() {
        guard appState.isRecording else { return }

        cancelPendingStop()
        isLatchedRecording = false
        audioCapture.stop()
        appState.isRecording = false
        appState.audioLevel = 0
        appState.statusMessage = "Finalizing..."

        restoreMute()

        let shortcutID = activeShortcutID
        let hasEnhancement = shortcutID.flatMap { appState.promptContent(forShortcutID: $0) } != nil

        if hasEnhancement {
            appState.overlayLabel = "Enhancing"
        } else {
            appState.overlayVisible = false
            overlayWindowController.hide()
        }

        deepgramClient.closeStream { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.appState.statusMessage = "Idle"
                self.appState.addLog("Listening stopped.", level: .info)
                await self.pasteFinalTranscript(shortcutID: shortcutID)
                self.activeShortcutID = nil
            }
        }
    }

    private func scheduleStopRecording() {
        cancelPendingStop()
        let workItem = DispatchWorkItem { [weak self] in
            self?.stopRecording()
        }
        stopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + stopDelay, execute: workItem)
    }

    private func cancelPendingStop() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
    }

    // MARK: - Cancel Recording

    private func cancelRecording() {
        guard appState.isRecording else { return }

        cancelPendingStop()
        audioCapture.stop()
        deepgramClient.disconnect()
        isLatchedRecording = false
        activeShortcutID = nil
        restoreMute()
        appState.isRecording = false
        appState.audioLevel = 0
        appState.overlayVisible = false
        overlayWindowController.hide()
        playSound("Pop")
        appState.statusMessage = "Cancelled."
        appState.addLog("Recording cancelled.", level: .info)
    }

    // MARK: - ESC Key Monitor

    private func startEscMonitor() {
        let escKeyCode = UInt16(kVK_Escape)

        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escKeyCode else { return }
            Task { @MainActor in
                guard let self, self.appState.isRecording, self.appState.escToCancelRecording else { return }
                self.cancelRecording()
            }
        }

        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escKeyCode else { return event }
            Task { @MainActor in
                guard let self, self.appState.isRecording, self.appState.escToCancelRecording else { return }
                self.cancelRecording()
            }
            return event
        }
    }

    private func stopEscMonitor() {
        if let monitor = escGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            escGlobalMonitor = nil
        }
        if let monitor = escLocalMonitor {
            NSEvent.removeMonitor(monitor)
            escLocalMonitor = nil
        }
    }

    // MARK: - Media Control

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
        guard let device = defaultOutputDevice() else { return }
        var value: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    private func isSystemMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
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

    // MARK: - Sound Effects

    private func playSound(_ name: String) {
        guard appState.playSoundEffects else { return }
        NSSound(named: name)?.play()
    }

    private func playErrorSound() {
        NSSound(named: "Basso")?.play()
    }

    // MARK: - Paste with Enhancement

    private func pasteFinalTranscript(shortcutID: UUID?) async {
        let finalText = appState.finalTranscript.trimmed
        let fallbackText = appState.lastTranscript.trimmed
        let rawText = finalText.isEmpty ? fallbackText : finalText
        guard !rawText.isEmpty else {
            appState.addLog("No transcript to paste.", level: .warning)
            hideOverlay()
            playSound("Pop")
            return
        }

        // Enhancement via OpenRouter
        var enhancedText: String?
        var enhancementFailed = false
        if let shortcutID,
           let prompt = appState.promptContent(forShortcutID: shortcutID) {
            if !appState.hasOpenRouterCredentials {
                let missing = appState.openRouterApiKey.trimmed.isEmpty ? "API key" : "model"
                appState.statusMessage = "Enhancement skipped: missing \(missing)."
                appState.addLog("Enhancement skipped: OpenRouter \(missing) is not set.", level: .warning)
                enhancementFailed = true
            } else {
                appState.statusMessage = "Enhancing..."
                appState.addLog("Sending transcript to OpenRouter for enhancement.", level: .info)
                do {
                    let enhanced = try await OpenRouterClient.enhance(
                        transcript: rawText,
                        prompt: prompt,
                        apiKey: appState.openRouterApiKey.trimmed,
                        model: appState.openRouterModel.trimmed
                    )
                    let trimmed = enhanced.trimmed
                    if !trimmed.isEmpty {
                        enhancedText = trimmed
                        appState.addLog("Transcript enhanced successfully.", level: .info)
                    }
                } catch {
                    appState.statusMessage = "Enhancement failed."
                    appState.addLog("Enhancement failed: \(error.localizedDescription)", level: .error)
                    enhancementFailed = true
                }
            }
        }

        hideOverlay()

        let textToPaste = enhancedText ?? rawText
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(textToPaste, forType: .string)
        appState.addTranscriptToHistory(rawText, enhancedText: enhancedText)
        appState.addLog("Transcript copied to clipboard.", level: .info)
        appState.statusMessage = "Idle"

        if !AXIsProcessTrusted() {
            appState.addLog("Accessibility permission not granted. Enable it to allow paste automation.", level: .warning)
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            appState.addLog("Failed to create CGEventSource for paste.", level: .error)
            snapshot.restore(to: pasteboard)
            if enhancementFailed { playErrorSound() } else { playSound("Pop") }
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        appState.addLog("Paste command sent (Cmd+V).", level: .info)

        if enhancementFailed { playErrorSound() } else { playSound("Pop") }

        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
            snapshot.restore(to: pasteboard)
        }
    }

    private func hideOverlay() {
        guard appState.overlayVisible else { return }
        appState.overlayVisible = false
        overlayWindowController.hide()
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

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            return dataByType
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restoredItems = items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
