import XCTest
@testable import VibeScribeCore

@MainActor
final class FinalizeWatchdogTests: XCTestCase {
    func testWatchdogFinalizesOnceAndIgnoresLateCloseCallback() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let audio = FakeAudioCapturePort()
        let deepgram = FakeDeepgramPort()
        let sound = FakeSoundPort()

        var finalizationCount = 0

        let runtime = RecordingRuntime(
            audioCapture: audio,
            deepgram: deepgram,
            scheduler: scheduler,
            clock: clock,
            activeApplicationProvider: { nil },
            audioInputSelectionProvider: {
                ResolvedAudioInputSelection(
                    selection: .systemDefault,
                    selectedDevice: nil,
                    systemDefaultDevice: nil
                )
            },
            languageProvider: { .automatic },
            apiKeyProvider: { "dg_key" },
            resolvedEnhancementPromptProvider: { _, _ in
                EnhancementPromptContext(
                    name: "Clean",
                    content: "clean this",
                    isForActiveApp: false
                )
            },
            playSoundEffectsEnabledProvider: { false },
            muteDuringRecordingProvider: { false },
            soundPort: sound
        )

        runtime.onFinalizeRequested = { _ in
            finalizationCount += 1
        }

        let ownerID = UUID()
        runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .click, latched: true))
        runtime.handle(action: .stop)
        XCTAssertEqual(runtime.phase, .finalizing)

        scheduler.advance(by: 1.2)
        await Task.yield()

        XCTAssertEqual(finalizationCount, 1)
        XCTAssertEqual(runtime.phase, .idle)

        deepgram.completeClose()
        await Task.yield()

        XCTAssertEqual(finalizationCount, 1, "Late close callback must not double-finalize")
    }
}
