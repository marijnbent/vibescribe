import ApplicationServices
import Foundation

@MainActor
final class PasteRuntime {
    typealias Enhancer = @Sendable (_ transcript: String, _ prompt: String, _ apiKey: String, _ model: String) async throws -> String

    private let appState: AppState
    private let pasteboard: PasteboardPort
    private let soundPort: SoundPort
    private let scheduler: SchedulerPort
    private let enhancer: Enhancer
    private let restoreClipboardAfterPaste: () -> Bool
    private let clipboardRestoreDelay: TimeInterval

    var onHideOverlay: (() -> Void)?

    init(
        appState: AppState,
        pasteboard: PasteboardPort,
        soundPort: SoundPort,
        scheduler: SchedulerPort,
        enhancer: @escaping Enhancer,
        restoreClipboardAfterPaste: @escaping () -> Bool = { false },
        clipboardRestoreDelay: TimeInterval = 0.2
    ) {
        self.appState = appState
        self.pasteboard = pasteboard
        self.soundPort = soundPort
        self.scheduler = scheduler
        self.enhancer = enhancer
        self.restoreClipboardAfterPaste = restoreClipboardAfterPaste
        self.clipboardRestoreDelay = clipboardRestoreDelay
    }

    func pasteFinalTranscript(enhancementPrompt: EnhancementPromptContext?, transcriptionError: String?) async {
        let finalText = appState.finalTranscript.trimmed
        let fallbackText = appState.lastTranscript.trimmed
        let rawText = finalText.isEmpty ? fallbackText : finalText

        guard !rawText.isEmpty else {
            let reason = transcriptionError ?? TranscriptHistoryEntry.emptyTranscriptionMessage
            appState.appStatus = .transcriptionFailed
            appState.addLog("Transcription failed: \(reason)", level: .error)
            appState.addTranscriptionFailureToHistory(reason: reason)
            onHideOverlay?()
            if transcriptionError != nil {
                playErrorSound(force: true)
            } else {
                playSound("Pop")
            }
            return
        }

        defer {
            onHideOverlay?()
        }

        var enhancedText: String?
        var enhancementFailed = false
        var enhancementError: String?

        if let prompt = enhancementPrompt {
            if !appState.hasOpenRouterCredentials {
                let missing = appState.openRouterApiKey.trimmed.isEmpty ? "API key" : "model"
                let reason = "OpenRouter \(missing) is not set."
                appState.appStatus = .enhancementSkippedMissing(missing)
                appState.addLog("Enhancement skipped: \(reason)", level: .warning)
                enhancementError = reason
                enhancementFailed = true
            } else {
                let model = appState.openRouterModel.trimmed
                let requestStart = Date()
                appState.appStatus = .enhancing
                appState.addLog("Sending transcript to OpenRouter for enhancement (model: \(model)).", level: .info)
                do {
                    let enhanced = try await enhancer(
                        rawText,
                        prompt.content,
                        appState.openRouterApiKey.trimmed,
                        model
                    )
                    let latencyMs = Int(Date().timeIntervalSince(requestStart) * 1_000)
                    let trimmed = enhanced.trimmed
                    if !trimmed.isEmpty {
                        enhancedText = trimmed
                        appState.addLog("Transcript enhanced successfully (model: \(model), \(latencyMs) ms).", level: .info)
                    } else {
                        appState.appStatus = .enhancementFailedPastingOriginal
                        appState.addLog(
                            "Enhancement failed (model: \(model), \(latencyMs) ms): OpenRouter returned empty content.",
                            level: .error
                        )
                        enhancementError = "OpenRouter returned empty content."
                        enhancementFailed = true
                    }
                } catch {
                    let latencyMs = Int(Date().timeIntervalSince(requestStart) * 1_000)
                    let reason = error.localizedDescription.trimmed.isEmpty
                        ? String(describing: error)
                        : error.localizedDescription
                    appState.appStatus = .enhancementFailedPastingOriginal
                    appState.addLog(
                        "Enhancement failed (model: \(model), \(latencyMs) ms): \(reason)",
                        level: .error
                    )
                    enhancementError = reason
                    enhancementFailed = true
                }
            }
        }

        let textToPaste = enhancedText ?? rawText
        let shouldRestoreClipboard = restoreClipboardAfterPaste()
        let snapshot = shouldRestoreClipboard ? pasteboard.snapshot() : nil
        pasteboard.writeString(textToPaste)

        appState.addTranscriptToHistory(
            rawText,
            enhancedText: enhancedText,
            transcriptionError: transcriptionError,
            enhancementError: enhancementError,
            promptName: enhancementPrompt?.name,
            usedActiveAppPrompt: enhancementPrompt?.isForActiveApp ?? false
        )
        if let transcriptionError {
            appState.addLog("Transcript completed with warning: \(transcriptionError)", level: .warning)
            playErrorSound(force: true)
        }
        if enhancementFailed {
            appState.addLog("Pasted original transcription because enhancement failed.", level: .warning)
        }
        appState.addLog("Transcript copied to clipboard.", level: .info)
        appState.appStatus = .idle

        if !AXIsProcessTrusted() {
            appState.addLog("Accessibility permission not granted. Enable it to allow paste automation.", level: .warning)
        }

        let didAutoPaste = pasteboard.sendPasteCommand()
        guard didAutoPaste else {
            appState.addLog("Failed to send paste command (Cmd+V).", level: .error)
            if enhancementFailed { playErrorSound() } else { playSound("Pop") }
            return
        }

        appState.addLog("Paste command sent (Cmd+V).", level: .info)

        if enhancementFailed { playErrorSound() } else { playSound("Pop") }

        guard shouldRestoreClipboard, let snapshot else { return }
        _ = scheduler.schedule(after: clipboardRestoreDelay) { [weak self] in
            self?.pasteboard.restore(snapshot)
        }
    }

    private func playSound(_ name: String) {
        guard appState.playSoundEffects else { return }
        soundPort.play(named: name)
    }

    private func playErrorSound(force: Bool = false) {
        guard force || appState.playSoundEffects else { return }
        soundPort.play(named: "Basso")
    }
}
