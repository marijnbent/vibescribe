import XCTest
@testable import VibeScribeCore

@MainActor
final class PasteRuntimeTests: XCTestCase {
    func testPasteKeepsClipboardByDefaultAfterAutoPaste() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
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

        scheduler.advance(by: 0.2)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertTrue(events.contains(where: matchesIdleStatus))
    }

    func testPasteCanRestoreClipboardAfterAutoPasteWhenEnabled() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
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

        scheduler.advance(by: 0.2)
        XCTAssertEqual(pasteboard.restoredSnapshots.count, 1)
        XCTAssertEqual(pasteboard.restoredSnapshots[0], pasteboard.currentSnapshot)
    }

    func testOverlayHidesAfterPasteCommandAttempt() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        var events: [String] = []

        pasteboard.onWriteString = { _ in
            events.append("write")
        }
        pasteboard.onSendPasteCommand = {
            events.append("paste")
        }

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
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
        let runtime = PasteRuntime(
            pasteboard: pasteboard,
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
                transcriptionError: nil
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
        XCTAssertEqual(historyEntry?.usedActiveAppPrompt, false)
        XCTAssertTrue(emittedEvents.contains(where: matchesIdleStatus))
    }

    func testEnhancementHistoryStoresActiveAppPromptMetadata() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        let runtime = PasteRuntime(
            pasteboard: pasteboard,
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
        XCTAssertEqual(historyEntry?.usedActiveAppPrompt, true)
    }

    func testPasteCommandFailureKeepsClipboardByDefault() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        pasteboard.sendPasteCommandResult = false

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
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
    }

    func testPasteCommandFailureDoesNotRestoreClipboardEvenWhenEnabled() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        pasteboard.sendPasteCommandResult = false

        let runtime = PasteRuntime(
            pasteboard: pasteboard,
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

        scheduler.advance(by: 0.2)
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
}
