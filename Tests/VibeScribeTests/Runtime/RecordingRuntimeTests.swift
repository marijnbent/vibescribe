import AppKit
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
        let harness = makeHarness(
            resolvedEnhancementPromptProvider: { _, _ in enhancement }
        )

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        harness.runtime.handle(action: .stop)
        harness.deepgram.completeClose()
        await Task.yield()

        XCTAssertEqual(harness.finalizations.value.first?.enhancementPrompt, enhancement)
    }

    func testCapturesActiveAppPromptAndIconAtRecordingStart() async {
        let slackIcon = NSImage(size: NSSize(width: 18, height: 18))
        var activeApplication = ActiveApplicationContext(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            icon: slackIcon
        )
        let harness = makeHarness(
            activeApplicationProvider: { activeApplication },
            resolvedEnhancementPromptProvider: { _, bundleIdentifier in
                guard bundleIdentifier == "com.tinyspeck.slackmacgap" else { return nil }
                return EnhancementPromptContext(
                    name: "Slack tidy",
                    content: "clean this",
                    isForActiveApp: true
                )
            }
        )
        var overlayUpdates: [(Bool, String, Bool)] = []
        harness.runtime.onOverlayUpdate = { visible, label, icon in
            overlayUpdates.append((visible, label, icon != nil))
        }

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))

        activeApplication = ActiveApplicationContext(
            bundleIdentifier: "com.apple.TextEdit",
            icon: nil
        )

        harness.runtime.handle(action: .stop)
        harness.deepgram.completeClose()
        await Task.yield()

        XCTAssertEqual(harness.finalizations.value.first?.enhancementPrompt?.name, "Slack tidy")
        XCTAssertEqual(overlayUpdates.first?.0, true)
        XCTAssertEqual(overlayUpdates.first?.1, "Listening")
        XCTAssertEqual(overlayUpdates.first?.2, true)
        XCTAssertEqual(overlayUpdates.last?.1, "Enhancing")
        XCTAssertEqual(overlayUpdates.last?.2, true)
    }

    func testStopKeepsOverlayVisibleWithoutEnhancementUntilPasteFlowTakesOver() async {
        let harness = makeHarness()
        var overlayUpdates: [(Bool, String, Bool)] = []
        harness.runtime.onOverlayUpdate = { visible, label, icon in
            overlayUpdates.append((visible, label, icon != nil))
        }

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        harness.runtime.handle(action: .stop)
        harness.deepgram.completeClose()
        await Task.yield()

        XCTAssertEqual(overlayUpdates.count, 2)
        XCTAssertEqual(overlayUpdates[0].0, true)
        XCTAssertEqual(overlayUpdates[0].1, "Listening")
        XCTAssertEqual(overlayUpdates[1].0, true)
        XCTAssertEqual(overlayUpdates[1].1, "Listening")
    }

    private func makeHarness(
        activeApplicationProvider: @escaping () -> ActiveApplicationContext? = { nil },
        resolvedEnhancementPromptProvider: @escaping (UUID?, String?) -> EnhancementPromptContext? = { _, _ in nil }
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
            activeApplicationProvider: activeApplicationProvider,
            languageProvider: { .automatic },
            apiKeyProvider: { "dg_key" },
            resolvedEnhancementPromptProvider: resolvedEnhancementPromptProvider,
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
