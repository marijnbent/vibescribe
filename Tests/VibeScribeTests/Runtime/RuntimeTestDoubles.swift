import AVFoundation
import Foundation
@testable import VibeScribeCore

final class ManualClock: ClockPort {
    var currentTime: TimeInterval = 0

    func now() -> TimeInterval {
        currentTime
    }
}

final class ManualScheduledTask: CancellableTask {
    fileprivate var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

final class ManualScheduler: SchedulerPort {
    private struct Entry {
        let deadline: TimeInterval
        let block: () -> Void
        let token: ManualScheduledTask
    }

    private let clock: ManualClock
    private var entries: [Entry] = []

    init(clock: ManualClock) {
        self.clock = clock
    }

    @discardableResult
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> CancellableTask {
        let token = ManualScheduledTask()
        let entry = Entry(deadline: clock.currentTime + delay, block: block, token: token)
        entries.append(entry)
        entries.sort { $0.deadline < $1.deadline }
        return token
    }

    func advance(by delta: TimeInterval) {
        clock.currentTime += delta
        runDueTasks()
    }

    func runAllDueTasks() {
        runDueTasks()
    }

    private func runDueTasks() {
        var remaining: [Entry] = []
        for entry in entries {
            if entry.deadline <= clock.currentTime {
                if !entry.token.isCancelled {
                    entry.block()
                }
            } else {
                remaining.append(entry)
            }
        }
        entries = remaining
    }
}

final class FakeAudioCapturePort: AudioCapturePort {
    enum TestError: Error {
        case startFailed
    }

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onConfigurationChanged: (() -> Void)?
    var startCallCount = 0
    var stopCallCount = 0
    var startFormat = AudioStreamFormat(sampleRate: 16_000, channels: 1)
    var shouldFailStart = false

    func start() throws -> AudioStreamFormat {
        startCallCount += 1
        if shouldFailStart {
            throw TestError.startFailed
        }
        return startFormat
    }

    func stop() {
        stopCallCount += 1
    }

    func emitConfigurationChange() {
        onConfigurationChanged?()
    }
}

final class FakeDeepgramPort: DeepgramPort {
    struct ConnectCall {
        let apiKey: String
        let format: AudioStreamFormat
        let language: DeepgramLanguage
    }

    var onTranscriptEvent: ((String, Bool) -> Void)?
    var onLog: ((String, LogLevel) -> Void)?
    var onTranscriptionError: ((String) -> Void)?
    var onConnectionDropped: ((String) -> Void)?

    var connectCalls: [ConnectCall] = []
    var sendAudioCallCount = 0
    var disconnectCallCount = 0
    var closeStreamCallCount = 0
    var closeCallbacks: [() -> Void] = []

    func connect(apiKey: String, format: AudioStreamFormat, language: DeepgramLanguage) {
        connectCalls.append(ConnectCall(apiKey: apiKey, format: format, language: language))
    }

    func sendAudio(buffer: AVAudioPCMBuffer) {
        sendAudioCallCount += 1
    }

    func closeStream(onClosed: @escaping () -> Void) {
        closeStreamCallCount += 1
        closeCallbacks.append(onClosed)
    }

    func disconnect() {
        disconnectCallCount += 1
    }

    func emitConnectionDropped(_ reason: String) {
        onConnectionDropped?(reason)
    }

    func emitTranscript(_ text: String, isFinal: Bool) {
        onTranscriptEvent?(text, isFinal)
    }

    func emitTranscriptionError(_ message: String) {
        onTranscriptionError?(message)
    }

    func completeClose(index: Int = 0) {
        guard closeCallbacks.indices.contains(index) else { return }
        let cb = closeCallbacks[index]
        cb()
    }
}

final class FakeSoundPort: SoundPort {
    var playedNames: [String] = []

    func play(named: String) {
        playedNames.append(named)
    }
}

final class FakePasteboardPort: PasteboardPort {
    var currentSnapshot = PasteboardSnapshotPayload(items: [])
    var writtenStrings: [String] = []
    var restoredSnapshots: [PasteboardSnapshotPayload] = []
    var sendPasteCommandResult = true
    var sendPasteCommandCallCount = 0
    var onWriteString: ((String) -> Void)?
    var onSendPasteCommand: (() -> Void)?

    func snapshot() -> PasteboardSnapshotPayload {
        currentSnapshot
    }

    func writeString(_ value: String) {
        writtenStrings.append(value)
        onWriteString?(value)
    }

    func restore(_ snapshot: PasteboardSnapshotPayload) {
        restoredSnapshots.append(snapshot)
    }

    func sendPasteCommand() -> Bool {
        sendPasteCommandCallCount += 1
        onSendPasteCommand?()
        return sendPasteCommandResult
    }
}
