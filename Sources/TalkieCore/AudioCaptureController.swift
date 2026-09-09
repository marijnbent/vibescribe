@preconcurrency import AVFoundation
import Foundation

struct AudioStreamFormat: Sendable, Equatable {
    let sampleRate: Int
    let channels: Int
}

final class AudioCaptureController: NSObject, @unchecked Sendable {
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
    private let sessionQueue = DispatchQueue(label: "Talkie.AudioCapture.Session")
    private let outputQueue = DispatchQueue(label: "Talkie.AudioCapture.Output")
    private let callbackLock = NSLock()

    private var session: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var currentInputDeviceUniqueID: String?
    private var currentFormat: AudioStreamFormat?
    private var activeSessionID: UUID?
    private var outputSessionID: UUID?
    private var audioChunkHandler: (@Sendable (UUID, Linear16AudioChunk) -> Void)?
    private var configurationChangedHandler: (@Sendable (UUID) -> Void)?

    var onAudioChunk: (@Sendable (UUID, Linear16AudioChunk) -> Void)? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return audioChunkHandler
        }
        set {
            callbackLock.lock()
            audioChunkHandler = newValue
            callbackLock.unlock()
        }
    }

    var onConfigurationChanged: (@Sendable (UUID) -> Void)? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return configurationChangedHandler
        }
        set {
            callbackLock.lock()
            configurationChangedHandler = newValue
            callbackLock.unlock()
        }
    }

    init(preferredInputProvider: @escaping () -> AudioInputSelection = { .systemDefault }) {
        self.preferredInputProvider = preferredInputProvider
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start(sessionID: UUID) async throws -> AudioStreamFormat {
        let selection = preferredInputProvider()
        try Task.checkCancellation()

        let format = try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    continuation.resume(returning: try startOnSessionQueue(
                        sessionID: sessionID,
                        selection: selection
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        if Task.isCancelled {
            await stop(sessionID: sessionID)
            throw CancellationError()
        }
        return format
    }

    func stop(sessionID: UUID) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                stopSessionOnSessionQueue(sessionID: sessionID)
                continuation.resume()
            }
        }
    }

    private func startOnSessionQueue(
        sessionID: UUID,
        selection: AudioInputSelection
    ) throws -> AudioStreamFormat {
        if activeSessionID == sessionID, let currentFormat {
            return currentFormat
        }

        if let activeSessionID {
            stopSessionOnSessionQueue(sessionID: activeSessionID)
        }

        guard let device = AudioInputCatalog.captureDevice(for: selection) else {
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
        activeSessionID = sessionID
        setOutputSessionID(sessionID)
        installObservers(for: session)

        session.startRunning()

        return format
    }

    private func stopSessionOnSessionQueue(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        setOutputSessionID(nil)
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        session?.stopRunning()
        removeObservers()
        session = nil
        audioOutput = nil
        currentInputDeviceUniqueID = nil
        currentFormat = nil
        activeSessionID = nil
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
        guard let observedSession = notification.object as? AVCaptureSession else { return }
        sessionQueue.async { [weak self] in
            guard let self, self.session === observedSession else { return }
            self.handleConfigurationChangeOnSessionQueue()
        }
    }

    @objc private func handleCaptureDeviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        let uniqueID = device.uniqueID
        sessionQueue.async { [weak self] in
            guard let self, uniqueID == self.currentInputDeviceUniqueID else { return }
            self.handleConfigurationChangeOnSessionQueue()
        }
    }

    private func handleConfigurationChangeOnSessionQueue() {
        guard let sessionID = activeSessionID else { return }
        stopSessionOnSessionQueue(sessionID: sessionID)
        let callback = readConfigurationChangedHandler()
        callback?(sessionID)
    }

    private func setOutputSessionID(_ sessionID: UUID?) {
        callbackLock.lock()
        outputSessionID = sessionID
        callbackLock.unlock()
    }

    private func readConfigurationChangedHandler() -> (@Sendable (UUID) -> Void)? {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        return configurationChangedHandler
    }

    private func outputCallback() -> (
        UUID,
        @Sendable (UUID, Linear16AudioChunk) -> Void
    )? {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        guard let outputSessionID, let audioChunkHandler else { return nil }
        return (outputSessionID, audioChunkHandler)
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

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
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

        do {
            try converter.convert(to: targetBuffer, from: sourceBuffer)
            return targetBuffer
        } catch {
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
        guard let (sessionID, callback) = outputCallback(),
              let buffer = Self.pcmBuffer(from: sampleBuffer),
              let chunk = AudioBufferConverter.linear16Chunk(from: buffer) else {
            return
        }
        callback(sessionID, chunk)
    }
}
