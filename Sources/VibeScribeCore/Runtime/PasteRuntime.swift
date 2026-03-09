import ApplicationServices
import Foundation

struct FinalizedTranscriptSession {
    let finalTranscript: String
    let lastTranscript: String
    let enhancementPrompt: EnhancementPromptContext?
    let transcriptionError: String?
}

struct PasteRuntimeSettings {
    let openRouterApiKey: String
    let openRouterModel: String
    let playSoundEffects: Bool
    let restoreClipboardAfterPaste: Bool

    var hasOpenRouterCredentials: Bool {
        !openRouterApiKey.trimmed.isEmpty && !openRouterModel.trimmed.isEmpty
    }
}

enum PasteRuntimeEvent {
    case status(AppStatus)
    case log(String, LogLevel)
    case historyEntry(TranscriptHistoryEntry)
    case hideOverlay
    case playSound(String)
}

@MainActor
final class PasteRuntime {
    typealias Enhancer = @Sendable (_ transcript: String, _ prompt: String, _ apiKey: String, _ model: String) async throws -> String

    private let pasteboard: PasteboardPort
    private let scheduler: SchedulerPort
    private let enhancer: Enhancer
    private let clipboardRestoreDelay: TimeInterval

    var onEvent: ((PasteRuntimeEvent) -> Void)?

    init(
        pasteboard: PasteboardPort,
        scheduler: SchedulerPort,
        enhancer: @escaping Enhancer,
        clipboardRestoreDelay: TimeInterval = 0.2
    ) {
        self.pasteboard = pasteboard
        self.scheduler = scheduler
        self.enhancer = enhancer
        self.clipboardRestoreDelay = clipboardRestoreDelay
    }

    func process(session: FinalizedTranscriptSession, settings: PasteRuntimeSettings) async {
        let finalText = session.finalTranscript.trimmed
        let fallbackText = session.lastTranscript.trimmed
        let rawText = finalText.isEmpty ? fallbackText : finalText

        guard !rawText.isEmpty else {
            let reason = session.transcriptionError ?? TranscriptHistoryEntry.emptyTranscriptionMessage
            emit(.status(.transcriptionFailed))
            emit(.log("Transcription failed: \(reason)", .error))
            emit(.historyEntry(
                TranscriptHistoryEntry(
                    timestamp: Date(),
                    text: "",
                    transcriptionError: reason
                )
            ))
            emit(.hideOverlay)
            if settings.playSoundEffects || session.transcriptionError != nil {
                emit(.playSound(session.transcriptionError != nil ? "Basso" : "Pop"))
            }
            return
        }

        defer {
            emit(.hideOverlay)
        }

        var enhancedText: String?
        var enhancementFailed = false
        var enhancementError: String?

        if let prompt = session.enhancementPrompt {
            if !settings.hasOpenRouterCredentials {
                let missing = settings.openRouterApiKey.trimmed.isEmpty ? "API key" : "model"
                let reason = "OpenRouter \(missing) is not set."
                emit(.status(.enhancementSkippedMissing(missing)))
                emit(.log("Enhancement skipped: \(reason)", .warning))
                enhancementError = reason
                enhancementFailed = true
            } else {
                let model = settings.openRouterModel.trimmed
                let requestStart = Date()
                emit(.status(.enhancing))
                emit(.log("Sending transcript to OpenRouter for enhancement (model: \(model)).", .info))
                do {
                    let enhanced = try await enhancer(
                        rawText,
                        prompt.content,
                        settings.openRouterApiKey.trimmed,
                        model
                    )
                    let latencyMs = Int(Date().timeIntervalSince(requestStart) * 1_000)
                    let trimmed = enhanced.trimmed
                    if !trimmed.isEmpty {
                        enhancedText = trimmed
                        emit(.log("Transcript enhanced successfully (model: \(model), \(latencyMs) ms).", .info))
                    } else {
                        emit(.status(.enhancementFailedPastingOriginal))
                        emit(.log(
                            "Enhancement failed (model: \(model), \(latencyMs) ms): OpenRouter returned empty content.",
                            .error
                        ))
                        enhancementError = "OpenRouter returned empty content."
                        enhancementFailed = true
                    }
                } catch {
                    let latencyMs = Int(Date().timeIntervalSince(requestStart) * 1_000)
                    let reason = error.localizedDescription.trimmed.isEmpty
                        ? String(describing: error)
                        : error.localizedDescription
                    emit(.status(.enhancementFailedPastingOriginal))
                    emit(.log("Enhancement failed (model: \(model), \(latencyMs) ms): \(reason)", .error))
                    enhancementError = reason
                    enhancementFailed = true
                }
            }
        }

        let textToPaste = enhancedText ?? rawText
        let snapshot = settings.restoreClipboardAfterPaste ? pasteboard.snapshot() : nil
        pasteboard.writeString(textToPaste)

        emit(.historyEntry(
            TranscriptHistoryEntry(
                timestamp: Date(),
                text: rawText,
                enhancedText: enhancedText,
                transcriptionError: session.transcriptionError,
                enhancementError: enhancementError,
                promptName: session.enhancementPrompt?.name,
                usedActiveAppPrompt: session.enhancementPrompt?.isForActiveApp ?? false
            )
        ))

        if let transcriptionError = session.transcriptionError {
            emit(.log("Transcript completed with warning: \(transcriptionError)", .warning))
            if settings.playSoundEffects || session.transcriptionError != nil {
                emit(.playSound("Basso"))
            }
        }
        if enhancementFailed {
            emit(.log("Pasted original transcription because enhancement failed.", .warning))
        }
        emit(.log("Transcript copied to clipboard.", .info))
        emit(.status(.idle))

        if !AXIsProcessTrusted() {
            emit(.log("Accessibility permission not granted. Enable it to allow paste automation.", .warning))
        }

        let didAutoPaste = pasteboard.sendPasteCommand()
        guard didAutoPaste else {
            emit(.log("Failed to send paste command (Cmd+V).", .error))
            if settings.playSoundEffects || enhancementFailed {
                emit(.playSound(enhancementFailed ? "Basso" : "Pop"))
            }
            return
        }

        emit(.log("Paste command sent (Cmd+V).", .info))

        if settings.playSoundEffects || enhancementFailed {
            emit(.playSound(enhancementFailed ? "Basso" : "Pop"))
        }

        guard settings.restoreClipboardAfterPaste, let snapshot else { return }
        _ = scheduler.schedule(after: clipboardRestoreDelay) { [weak self] in
            self?.pasteboard.restore(snapshot)
        }
    }

    private func emit(_ event: PasteRuntimeEvent) {
        onEvent?(event)
    }
}
