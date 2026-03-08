import XCTest
@testable import VibeScribeCore

@MainActor
final class PasteRuntimeTests: XCTestCase {
    private let defaultsKeys = [
        "VibeScribe.ApiKey",
        "VibeScribe.DeepgramLanguage",
        "VibeScribe.HistoryLimit",
        "VibeScribe.Shortcuts",
        "VibeScribe.OpenRouterApiKey",
        "VibeScribe.OpenRouterModel",
        "VibeScribe.Prompts",
        "VibeScribe.EnhancementPrompts",
        "VibeScribe.EscToCancelRecording",
        "VibeScribe.PlaySoundEffects",
        "VibeScribe.MuteMediaDuringRecording",
        "VibeScribe.RestoreClipboardAfterPaste",
        "VibeScribe.OverlayPosition"
    ]

    override func setUp() {
        super.setUp()
        for key in defaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in defaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testPasteKeepsClipboardByDefaultAfterAutoPaste() async {
        let appState = AppState()
        appState.historyLimit = .ten
        appState.finalTranscript = "hello world"

        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        let sound = FakeSoundPort()

        let runtime = PasteRuntime(
            appState: appState,
            pasteboard: pasteboard,
            soundPort: sound,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        await runtime.pasteFinalTranscript(enhancementPrompt: nil, transcriptionError: nil)

        XCTAssertEqual(pasteboard.writtenStrings.last, "hello world")
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)

        scheduler.advance(by: 0.2)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
        XCTAssertEqual(appState.appStatus, .idle)
    }

    func testPasteCanRestoreClipboardAfterAutoPasteWhenEnabled() async {
        let appState = AppState()
        appState.historyLimit = .ten
        appState.finalTranscript = "hello world"

        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        let sound = FakeSoundPort()

        let runtime = PasteRuntime(
            appState: appState,
            pasteboard: pasteboard,
            soundPort: sound,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" },
            restoreClipboardAfterPaste: { true }
        )

        await runtime.pasteFinalTranscript(enhancementPrompt: nil, transcriptionError: nil)

        XCTAssertEqual(pasteboard.writtenStrings.last, "hello world")
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)

        scheduler.advance(by: 0.2)
        XCTAssertEqual(pasteboard.restoredSnapshots.count, 1)
        XCTAssertEqual(pasteboard.restoredSnapshots[0], pasteboard.currentSnapshot)
    }

    func testEnhancementMissingCredentialsFallsBackToOriginalAndRecordsError() async {
        let appState = AppState()
        appState.historyLimit = .ten
        appState.finalTranscript = "raw transcript"
        appState.openRouterApiKey = ""
        appState.openRouterModel = ""

        let prompt = PromptConfig(id: UUID(), name: "Clean", content: "clean this")
        appState.prompts = [prompt]
        var shortcuts = appState.shortcuts
        shortcuts[0].promptID = prompt.id
        appState.shortcuts = shortcuts
        XCTAssertNotNil(appState.promptContent(forShortcutID: appState.shortcuts[0].id))

        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        let sound = FakeSoundPort()

        let runtime = PasteRuntime(
            appState: appState,
            pasteboard: pasteboard,
            soundPort: sound,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in
                XCTFail("Enhancer should not be called when credentials are missing")
                return ""
            }
        )

        await runtime.pasteFinalTranscript(enhancementPrompt: "clean this", transcriptionError: nil)

        XCTAssertEqual(pasteboard.writtenStrings.last, "raw transcript")
        XCTAssertEqual(appState.transcriptHistory.first?.enhancementError, "OpenRouter API key is not set.")
        XCTAssertEqual(appState.appStatus, .idle)
    }

    func testPasteCommandFailureKeepsClipboardByDefault() async {
        let appState = AppState()
        appState.historyLimit = .ten
        appState.finalTranscript = "hello world"

        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        pasteboard.sendPasteCommandResult = false
        let sound = FakeSoundPort()

        let runtime = PasteRuntime(
            appState: appState,
            pasteboard: pasteboard,
            soundPort: sound,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" }
        )

        await runtime.pasteFinalTranscript(enhancementPrompt: nil, transcriptionError: nil)

        XCTAssertEqual(pasteboard.writtenStrings.last, "hello world")
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
    }

    func testPasteCommandFailureDoesNotRestoreClipboardEvenWhenEnabled() async {
        let appState = AppState()
        appState.historyLimit = .ten
        appState.finalTranscript = "hello world"

        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let pasteboard = FakePasteboardPort()
        pasteboard.currentSnapshot = PasteboardSnapshotPayload(
            items: [["public.utf8-plain-text": Data("old".utf8)]]
        )
        pasteboard.sendPasteCommandResult = false
        let sound = FakeSoundPort()

        let runtime = PasteRuntime(
            appState: appState,
            pasteboard: pasteboard,
            soundPort: sound,
            scheduler: scheduler,
            enhancer: { _, _, _, _ in "" },
            restoreClipboardAfterPaste: { true }
        )

        await runtime.pasteFinalTranscript(enhancementPrompt: nil, transcriptionError: nil)

        XCTAssertEqual(pasteboard.writtenStrings.last, "hello world")
        XCTAssertEqual(pasteboard.sendPasteCommandCallCount, 1)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)

        scheduler.advance(by: 0.2)
        XCTAssertTrue(pasteboard.restoredSnapshots.isEmpty)
    }
}
