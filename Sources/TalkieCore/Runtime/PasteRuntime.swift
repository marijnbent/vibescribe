import ApplicationServices
import Foundation

struct FinalizedTranscriptSession {
    let finalTranscript: String
    let lastTranscript: String
    let enhancementPrompt: EnhancementPromptContext?
    let transcriptionError: String?
    let rawRecordingFileURL: URL?
    let transcriptionLanguage: DeepgramLanguage?

    init(
        finalTranscript: String,
        lastTranscript: String,
        enhancementPrompt: EnhancementPromptContext?,
        transcriptionError: String?,
        rawRecordingFileURL: URL? = nil,
        transcriptionLanguage: DeepgramLanguage? = nil
    ) {
        self.finalTranscript = finalTranscript
        self.lastTranscript = lastTranscript
        self.enhancementPrompt = enhancementPrompt
        self.transcriptionError = transcriptionError
        self.rawRecordingFileURL = rawRecordingFileURL
        self.transcriptionLanguage = transcriptionLanguage
    }
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
    private let pasteVerification: PasteVerificationPort
    private let scheduler: SchedulerPort
    private let enhancer: Enhancer
    private let pasteVerificationPollInterval: TimeInterval
    private let pasteVerificationTimeout: TimeInterval

    var onEvent: ((PasteRuntimeEvent) -> Void)?

    init(
        pasteboard: PasteboardPort,
        pasteVerification: PasteVerificationPort,
        scheduler: SchedulerPort,
        enhancer: @escaping Enhancer,
        pasteVerificationPollInterval: TimeInterval = 0.05,
        pasteVerificationTimeout: TimeInterval = 0.35
    ) {
        self.pasteboard = pasteboard
        self.pasteVerification = pasteVerification
        self.scheduler = scheduler
        self.enhancer = enhancer
        self.pasteVerificationPollInterval = pasteVerificationPollInterval
        self.pasteVerificationTimeout = pasteVerificationTimeout
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
                    transcriptionError: reason,
                    rawRecordingFileURL: session.rawRecordingFileURL,
                    transcriptionLanguage: session.transcriptionLanguage
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

        do {
            try Task.checkCancellation()

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
                        try Task.checkCancellation()

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
                    } catch is CancellationError {
                        throw CancellationError()
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

            try Task.checkCancellation()

            let textToPaste = enhancedText ?? rawText
            let snapshot = settings.restoreClipboardAfterPaste ? pasteboard.snapshot() : nil
            let preparedVerification = settings.restoreClipboardAfterPaste
                ? pasteVerification.prepare(expectedText: textToPaste)
                : nil
            pasteboard.writeString(textToPaste)

            emit(.historyEntry(
                TranscriptHistoryEntry(
                    timestamp: Date(),
                    text: rawText,
                    enhancedText: enhancedText,
                    transcriptionError: session.transcriptionError,
                    enhancementError: enhancementError,
                    promptName: session.enhancementPrompt?.name,
                    enhancementPromptText: session.enhancementPrompt?.content,
                    rawRecordingFileURL: session.rawRecordingFileURL,
                    transcriptionLanguage: session.transcriptionLanguage,
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

            try Task.checkCancellation()

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
            guard let preparedVerification else {
                emit(.log("Could not confirm auto-paste. Kept transcript on the clipboard.", .warning))
                return
            }

            schedulePasteVerification(
                preparedVerification,
                snapshot: snapshot,
                remainingAttempts: verificationAttemptCount
            )
        } catch is CancellationError {
            emit(.status(.cancelled))
            emit(.log("Recording cancelled.", .info))
        } catch {
            emit(.status(.cancelled))
            emit(.log("Recording cancelled.", .info))
        }
    }

    private func emit(_ event: PasteRuntimeEvent) {
        onEvent?(event)
    }

    private var verificationAttemptCount: Int {
        max(1, Int(ceil(pasteVerificationTimeout / pasteVerificationPollInterval)))
    }

    private func schedulePasteVerification(
        _ verification: PreparedPasteVerification,
        snapshot: PasteboardSnapshotPayload,
        remainingAttempts: Int
    ) {
        _ = scheduler.schedule(after: pasteVerificationPollInterval) { [weak self] in
            self?.performPasteVerification(
                verification,
                snapshot: snapshot,
                remainingAttempts: remainingAttempts
            )
        }
    }

    private func performPasteVerification(
        _ verification: PreparedPasteVerification,
        snapshot: PasteboardSnapshotPayload,
        remainingAttempts: Int
    ) {
        switch pasteVerification.check(verification) {
        case .confirmed:
            pasteboard.restore(snapshot)
            emit(.log("Auto-paste confirmed. Restored previous clipboard.", .info))
        case .pending:
            guard remainingAttempts > 1 else {
                handlePasteVerificationFailure(.timedOut)
                return
            }
            schedulePasteVerification(
                verification,
                snapshot: snapshot,
                remainingAttempts: remainingAttempts - 1
            )
        case .unconfirmed(let reason):
            handlePasteVerificationFailure(reason)
        }
    }

    private func handlePasteVerificationFailure(_ reason: PasteVerificationFailureReason) {
        guard reason != .timedOut else {
            emit(.log("Could not confirm auto-paste. Kept transcript on the clipboard.", .warning))
            return
        }
        emit(.log("Could not confirm auto-paste. Kept transcript on the clipboard.", .warning))
    }
}
