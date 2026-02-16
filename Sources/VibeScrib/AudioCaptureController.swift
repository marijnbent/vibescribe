import AVFoundation

struct AudioStreamFormat {
    let sampleRate: Int
    let channels: Int
}

final class AudioCaptureController {
    private let engine = AVAudioEngine()
    private var isRunning = false

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    func start() throws -> AudioStreamFormat {
        guard !isRunning else {
            if let format = currentFormat() {
                return format
            }
            return AudioStreamFormat(sampleRate: 16000, channels: 1)
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true

        return AudioStreamFormat(sampleRate: Int(format.sampleRate), channels: Int(format.channelCount))
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func currentFormat() -> AudioStreamFormat? {
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return nil }
        return AudioStreamFormat(sampleRate: Int(format.sampleRate), channels: Int(format.channelCount))
    }
}
