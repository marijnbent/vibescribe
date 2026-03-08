import XCTest
@testable import VibeScribeCore

@MainActor
final class RecordingRuntimeTests: XCTestCase {
    private struct RuntimeHarness {
        let runtime: RecordingRuntime
        let deepgram: FakeDeepgramPort
        let scheduler: ManualScheduler
        let statuses: Box<[AppStatus]>
        let finalizations: Box<[RecordingFinalization]>
    }

    func testReconnectsOnceThenStopsRetryingAndFinalizes() async {
        let harness = makeHarness()

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        XCTAssertEqual(harness.runtime.phase, .recording)
        XCTAssertEqual(harness.deepgram.connectCalls.count, 1)

        harness.deepgram.emitConnectionDropped("first")
        await Task.yield()
        harness.scheduler.advance(by: 0.4)
        await Task.yield()
        XCTAssertEqual(harness.deepgram.connectCalls.count, 2)

        harness.deepgram.emitConnectionDropped("second")
        await Task.yield()
        harness.scheduler.advance(by: 0.4)
        await Task.yield()
        XCTAssertEqual(harness.deepgram.connectCalls.count, 2, "Should not reconnect more than once")
        XCTAssertEqual(harness.statuses.value.last, .connectionLostReleaseToFinalize)

        harness.runtime.handle(action: .stop)
        XCTAssertEqual(harness.runtime.phase, .finalizing)
        XCTAssertEqual(harness.deepgram.closeStreamCallCount, 1)

        harness.deepgram.completeClose()
        await Task.yield()
        XCTAssertEqual(harness.finalizations.value.count, 1)
        XCTAssertEqual(harness.runtime.phase, .idle)
    }

    func testDoesNotReconnectWhileFinalizing() async {
        let harness = makeHarness()

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        harness.runtime.handle(action: .stop)
        XCTAssertEqual(harness.runtime.phase, .finalizing)

        harness.deepgram.emitConnectionDropped("during finalize")
        await Task.yield()
        harness.scheduler.advance(by: 1.0)
        await Task.yield()

        XCTAssertEqual(harness.deepgram.connectCalls.count, 1)
    }

    func testFinalizeIncludesResolvedEnhancementPromptMetadata() async {
        let enhancement = EnhancementPromptContext(
            name: "Slack tidy",
            content: "clean this",
            isForActiveApp: true
        )
        let harness = makeHarness(resolvedEnhancementPrompt: enhancement)

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        harness.runtime.handle(action: .stop)
        harness.deepgram.completeClose()
        await Task.yield()

        XCTAssertEqual(harness.finalizations.value.first?.enhancementPrompt, enhancement)
    }

    private func makeHarness(
        resolvedEnhancementPrompt: EnhancementPromptContext? = nil
    ) -> RuntimeHarness {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let audio = FakeAudioCapturePort()
        let deepgram = FakeDeepgramPort()
        let sound = FakeSoundPort()

        let statuses = Box<[AppStatus]>([])
        let finalizations = Box<[RecordingFinalization]>([])

        let runtime = RecordingRuntime(
            audioCapture: audio,
            deepgram: deepgram,
            scheduler: scheduler,
            clock: clock,
            languageProvider: { .automatic },
            apiKeyProvider: { "dg_key" },
            resolvedEnhancementPromptProvider: { _ in resolvedEnhancementPrompt },
            playSoundEffectsEnabledProvider: { false },
            muteDuringRecordingProvider: { false },
            soundPort: sound
        )

        runtime.onStatus = { status in
            statuses.value.append(status)
        }
        runtime.onFinalizeRequested = { finalization in
            finalizations.value.append(finalization)
        }

        return RuntimeHarness(
            runtime: runtime,
            deepgram: deepgram,
            scheduler: scheduler,
            statuses: statuses,
            finalizations: finalizations
        )
    }
}

private final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
