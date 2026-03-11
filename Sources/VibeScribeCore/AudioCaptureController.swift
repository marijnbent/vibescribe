@preconcurrency import AVFoundation
import Foundation

struct AudioStreamFormat {
    let sampleRate: Int
    let channels: Int
}

final class AudioCaptureController: NSObject {
    private final class ConverterInputSource: @unchecked Sendable {
        private let buffer: AVAudioPCMBuffer
        private var didProvideBuffer = false

        init(buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func nextBuffer(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
            if didProvideBuffer {
                outStatus.pointee = .endOfStream
                return nil
            }

            didProvideBuffer = true
            outStatus.pointee = .haveData
            return buffer
        }
    }

    private enum CaptureError: LocalizedError {
        case noInputDeviceAvailable
        case unsupportedInputFormat
        case failedToAddInput(String)
        case failedToAddOutput
        case failedToCreateInput(String)

        var errorDescription: String? {
            switch self {
            case .noInputDeviceAvailable:
                return "No audio input device is currently available."
            case .unsupportedInputFormat:
                return "The selected audio input uses an unsupported format."
            case .failedToAddInput(let name):
                return "Could not use \(name) as the recording input."
            case .failedToAddOutput:
                return "Could not configure audio capture output."
            case .failedToCreateInput(let message):
                return "Could not access the selected microphone: \(message)"
            }
        }
    }

    private let preferredInputProvider: () -> AudioInputSelection
    private let outputQueue = DispatchQueue(label: "VibeScribe.AudioCapture.Output")

    private var session: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var currentInputDeviceUniqueID: String?
    private var currentFormat: AudioStreamFormat?
    private var isRunning = false

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onConfigurationChanged: (() -> Void)?

    init(preferredInputProvider: @escaping () -> AudioInputSelection = { .systemDefault }) {
        self.preferredInputProvider = preferredInputProvider
        super.init()
    }

    deinit {
        removeObservers()
    }

    func start() throws -> AudioStreamFormat {
        guard !isRunning else {
            if let currentFormat {
                return currentFormat
            }
            return AudioStreamFormat(sampleRate: 16_000, channels: 1)
        }

        guard let device = AudioInputCatalog.captureDevice(for: preferredInputProvider()) else {
            throw CaptureError.noInputDeviceAvailable
        }

        guard let format = Self.streamFormat(for: device) else {
            throw CaptureError.unsupportedInputFormat
        }

        let session = AVCaptureSession()
        let audioOutput = AVCaptureAudioDataOutput()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw CaptureError.failedToAddInput(device.localizedName)
            }
            session.addInput(input)
        } catch let error as CaptureError {
            throw error
        } catch {
            throw CaptureError.failedToCreateInput(error.localizedDescription)
        }

        audioOutput.audioSettings = Self.outputAudioSettings()
        audioOutput.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(audioOutput) else {
            throw CaptureError.failedToAddOutput
        }
        session.addOutput(audioOutput)

        self.session = session
        self.audioOutput = audioOutput
        currentInputDeviceUniqueID = device.uniqueID
        currentFormat = format
        installObservers(for: session)

        session.startRunning()
        isRunning = true

        return format
    }

    func stop() {
        guard isRunning else { return }
        stopSession()
    }

    private func stopSession() {
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        session?.stopRunning()
        removeObservers()
        session = nil
        audioOutput = nil
        currentInputDeviceUniqueID = nil
        currentFormat = nil
        isRunning = false
    }

    private func installObservers(for session: AVCaptureSession) {
        removeObservers()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureDeviceDisconnected(_:)),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceWasDisconnected, object: nil)
    }

    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        handleConfigurationChange()
    }

    @objc private func handleCaptureDeviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        guard device.uniqueID == currentInputDeviceUniqueID else { return }
        handleConfigurationChange()
    }

    private func handleConfigurationChange() {
        guard isRunning else { return }
        stopSession()
        onConfigurationChanged?()
    }

    private static func streamFormat(for device: AVCaptureDevice) -> AudioStreamFormat? {
        let formatDescription = device.activeFormat.formatDescription
        guard let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        return AudioStreamFormat(
            sampleRate: Int(streamDescription.pointee.mSampleRate),
            channels: Int(streamDescription.pointee.mChannelsPerFrame)
        )
    }

    private static func outputAudioSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true,
        ]
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        var asbd = streamDescription.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd) else {
            return nil
        }

        let frameCapacity = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCapacity > 0,
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        sourceBuffer.frameLength = frameCapacity
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCapacity),
            into: sourceBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }

        if sourceFormat.commonFormat == .pcmFormatFloat32 && !sourceFormat.isInterleaved {
            return sourceBuffer
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: sourceFormat.channelCount,
            interleaved: false
        ),
        let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity),
        let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }

        let inputSource = ConverterInputSource(buffer: sourceBuffer)
        var conversionError: NSError?
        let statusResult = converter.convert(to: targetBuffer, error: &conversionError) { _, outStatus in
            inputSource.nextBuffer(outStatus)
        }

        guard conversionError == nil else { return nil }
        switch statusResult {
        case .haveData, .inputRanDry, .endOfStream:
            return targetBuffer
        case .error:
            return nil
        @unknown default:
            return nil
        }
    }
}

extension AudioCaptureController: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer?(buffer)
    }
}
