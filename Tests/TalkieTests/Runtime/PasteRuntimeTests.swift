import XCTest
@testable import TalkieCore

@MainActor
final class PasteRuntimeTests: XCTestCase {
    func testPasteKeepsClipboardByDefaultAfterAutoPaste() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        let pasteVerification = FakePasteVerificationPort()

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        var events: [PasteRuntimeEvent] = []
        runtime.onEvent = { events.append($0) }

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "hello world",
                lastTranscript: "",
                enhancementPrompt: nil,
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: false
            )
        )

        XCTAssertEqual(pasteboard.writtenStrings.last, "hello world")
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertEqual(pasteVerification.prepareCallCount, 0)
        XCTAssertEqual(pasteVerification.checkCallCount, 0)

        scheduler.advance(by: 0.5)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertTrue(events.contains(where: matchesIdleStatus))
    }

    func testPasteRestoresClipboardOnlyAfterConfirmedAutoPaste() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        let pasteVerification = FakePasteVerificationPort()
        pasteVerification.prepareResult = makePreparedPasteVerification(expectedText: "hello world")
        pasteVerification.checkResults = [.pending, .confirmed]

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "hello world",
                lastTranscript: "",
                enhancementPrompt: nil,
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: true
            )
        )

        XCTAssertEqual(pasteboard.writtenStrings.last, "hello world")
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertEqual(pasteVerification.prepareCallCount, 1)
        XCTAssertEqual(pasteVerification.checkCallCount, 0)

        scheduler.advance(by: 0.051)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertEqual(pasteVerification.checkCallCount, 1)

        scheduler.advance(by: 0.051)
        XCTAssertEqual(pasteboard.restoredSnapshots.count, 1)
        XCTAssertEqual(pasteboard.restoredSnapshots[0], pasteboard.currentSnapshot)
        XCTAssertEqual(pasteVerification.checkCallCount, 2)
    }

    func testOverlayHidesAfterPasteCommandAttempt() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        let pasteVerification = FakePasteVerificationPort()
        var events: [String] = []

        pasteboard.onWriteString = { _ in
            events.append("write")
        }
        pasteboard.onSendPasteCommand = {
            events.append("paste")
        }

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )
        runtime.onEvent = { event in
            if case .hideOverlay = event {
                events.append("hide")
            }
        }

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "hello world",
                lastTranscript: "",
                enhancementPrompt: nil,
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: false
            )
        )

        XCTAssertEqual(events, ["write", "paste", "hide"])
    }

    func testEnhancementMissingCredentialsFallsBackToOriginalAndRecordsError() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        let pasteVerification = FakePasteVerificationPort()
        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in
                XCTFail("Enhancer should not be called when credentials are missing")
                return ""
            }
        )

        var emittedEvents: [PasteRuntimeEvent] = []
        runtime.onEvent = { emittedEvents.append($0) }

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "raw transcript",
                lastTranscript: "",
                enhancementPrompt: EnhancementPromptContext(
                    name: "Clean",
                    content: "clean this",
                    isForActiveApp: false
                ),
                transcriptionError: nil,
                rawRecordingFileURL: URL(fileURLWithPath: "/tmp/raw.wav"),
                transcriptionLanguage: .english
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: false
            )
        )

        XCTAssertEqual(pasteboard.writtenStrings.last, "raw transcript")

        let historyEntry = emittedEvents.compactMap(historyEntry).first
        XCTAssertEqual(historyEntry?.enhancementError, "OpenRouter API key is not set.")
        XCTAssertEqual(historyEntry?.promptName, "Clean")
        XCTAssertEqual(historyEntry?.enhancementPromptText, "clean this")
        XCTAssertEqual(historyEntry?.rawRecordingFileURL, URL(fileURLWithPath: "/tmp/raw.wav"))
        XCTAssertEqual(historyEntry?.transcriptionLanguage, .english)
        XCTAssertEqual(historyEntry?.usedActiveAppPrompt, false)
        XCTAssertTrue(emittedEvents.contains(where: matchesIdleStatus))
    }

    func testEnhancementHistoryStoresActiveAppPromptMetadata() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        let pasteVerification = FakePasteVerificationPort()
        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { transcript, _, _, _ in transcript.uppercased() }
        )

        var emittedEvents: [PasteRuntimeEvent] = []
        runtime.onEvent = { emittedEvents.append($0) }

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "raw transcript",
                lastTranscript: "",
                enhancementPrompt: EnhancementPromptContext(
                    name: "Slack tidy",
                    content: "clean this",
                    isForActiveApp: true
                ),
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "sk-test",
                openRouterModel: "openai/gpt-4o-mini",
                playSoundEffects: false,
                restoreClipboardAfterPaste: false
            )
        )

        let historyEntry = emittedEvents.compactMap(historyEntry).first
        XCTAssertEqual(historyEntry?.promptName, "Slack tidy")
        XCTAssertEqual(historyEntry?.enhancementPromptText, "clean this")
        XCTAssertEqual(historyEntry?.usedActiveAppPrompt, true)
    }

    func testCancellationDuringEnhancementSkipsPasteAndEmitsCancelled() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        let pasteVerification = FakePasteVerificationPort()
        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in
                while !Task.isCancelled {
                    await Task.yield()
                }
                throw CancellationError()
            }
        )

        var emittedEvents: [PasteRuntimeEvent] = []
        runtime.onEvent = { emittedEvents.append($0) }

        let task = Task {
            await runtime.process(
                session: FinalizedTranscriptSession(
                    finalTranscript: "raw transcript",
                    lastTranscript: "",
                    enhancementPrompt: EnhancementPromptContext(
                        name: "Clean",
                        content: "clean this",
                        isForActiveApp: false
                    ),
                    transcriptionError: nil
                ),
                settings: PasteRuntimeSettings(
                    openRouterApiKey: "sk-test",
                    openRouterModel: "openai/gpt-4o-mini",
                    playSoundEffects: false,
                    restoreClipboardAfterPaste: false
                )
            )
        }

        await Task.yield()
        task.cancel()
        await task.value

        XCTAssertTrue(pasteboard.writtenStrings.isEmpty)
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 0)
        XCTAssertTrue(emittedEvents.contains(where: matchesCancelledStatus))
        XCTAssertTrue(emittedEvents.contains(where: isHideOverlayEvent))
    }

    func testRestoreEnabledKeepsClipboardWhenVerificationCannotPrepare() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        let pasteVerification = FakePasteVerificationPort()

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        var emittedEvents: [PasteRuntimeEvent] = []
        runtime.onEvent = { emittedEvents.append($0) }

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "hello world",
                lastTranscript: "",
                enhancementPrompt: nil,
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: true
            )
        )

        XCTAssertEqual(pasteVerification.prepareCallCount, 1)
        XCTAssertEqual(pasteVerification.checkCallCount, 0)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertTrue(emittedEvents.contains(where: matchesClipboardKeptLog))

        scheduler.advance(by: 0.5)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
    }

    func testRestoreEnabledKeepsClipboardWhenVerificationMismatches() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        let pasteVerification = FakePasteVerificationPort()
        pasteVerification.prepareResult = makePreparedPasteVerification(expectedText: "hello world")
        pasteVerification.checkResults = [.unconfirmed(.mismatch)]

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        var emittedEvents: [PasteRuntimeEvent] = []
        runtime.onEvent = { emittedEvents.append($0) }

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "hello world",
                lastTranscript: "",
                enhancementPrompt: nil,
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: true
            )
        )

        scheduler.advance(by: 0.051)

        XCTAssertEqual(pasteVerification.prepareCallCount, 1)
        XCTAssertEqual(pasteVerification.checkCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertTrue(emittedEvents.contains(where: matchesClipboardKeptLog))
    }

    func testRestoreEnabledKeepsClipboardWhenVerificationTimesOut() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        let pasteVerification = FakePasteVerificationPort()
        pasteVerification.prepareResult = makePreparedPasteVerification(expectedText: "hello world")

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        var emittedEvents: [PasteRuntimeEvent] = []
        runtime.onEvent = { emittedEvents.append($0) }

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "hello world",
                lastTranscript: "",
                enhancementPrompt: nil,
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: true
            )
        )

        for _ in 0..<7 {
            scheduler.advance(by: 0.051)
        }

        XCTAssertEqual(pasteVerification.prepareCallCount, 1)
        XCTAssertEqual(pasteVerification.checkCallCount, 7)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertTrue(emittedEvents.contains(where: matchesClipboardKeptLog))
    }

    func testPasteCommandFailureKeepsClipboardByDefault() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        pasteboard.sendPasteCommandResult = false
        let pasteVerification = FakePasteVerificationPort()

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "hello world",
                lastTranscript: "",
                enhancementPrompt: nil,
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: false
            )
        )

        XCTAssertEqual(pasteboard.writtenStrings.last, "hello world")
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertEqual(pasteVerification.prepareCallCount, 0)
        XCTAssertEqual(pasteVerification.checkCallCount, 0)
    }

    func testPasteCommandFailureDoesNotRestoreClipboardEvenWhenEnabled() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        pasteboard.sendPasteCommandResult = false
        let pasteVerification = FakePasteVerificationPort()
        pasteVerification.prepareResult = makePreparedPasteVerification(expectedText: "hello world")

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
            pasteVerification: pasteVerification,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        await runtime.process(
            session: FinalizedTranscriptSession(
                finalTranscript: "hello world",
                lastTranscript: "",
                enhancementPrompt: nil,
                transcriptionError: nil
            ),
            settings: PasteRuntimeSettings(
                openRouterApiKey: "",
                openRouterModel: "",
                playSoundEffects: false,
                restoreClipboardAfterPaste: true
            )
        )

        XCTAssertEqual(pasteboard.writtenStrings.last, "hello world")
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertEqual(pasteVerification.prepareCallCount, 1)
        XCTAssertEqual(pasteVerification.checkCallCount, 0)

        scheduler.advance(by: 0.5)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
    }

    private func historyEntry(from event: PasteRuntimeEvent) -> TranscriptHistoryEntry? {
        if case .historyEntry(let entry) = event {
            return entry
        }
        return nil
    }

    private func matchesIdleStatus(_ event: PasteRuntimeEvent) -> Bool {
        if case .status(.idle) = event {
            return true
        }
        return false
    }

    private func matchesCancelledStatus(_ event: PasteRuntimeEvent) -> Bool {
        if case .status(.cancelled) = event {
            return true
        }
        return false
    }

    private func isHideOverlayEvent(_ event: PasteRuntimeEvent) -> Bool {
        if case .hideOverlay = event {
            return true
        }
        return false
    }

    private func matchesClipboardKeptLog(_ event: PasteRuntimeEvent) -> Bool {
        if case .log("Could not confirm auto-paste. Kept transcript on the clipboard.", .warning) = event {
            return true
        }
        return false
    }
}
