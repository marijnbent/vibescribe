import Foundation
import AVFoundation

final class DeepgramClient: NSObject, @unchecked Sendable {
    private let session: URLSession
    private let queue = DispatchQueue(label: "VibeScribe.DeepgramClient")
    private let queueKey = DispatchSpecificKey<Void>()
    private var task: URLSessionWebSocketTask?
    private var isConnected = false
    private var isClosing = false
    private let onTranscriptEvent: (@Sendable (String, Bool) -> Void)?
    private let onLog: (@Sendable (String, LogLevel) -> Void)?
    private let onTranscriptionError: (@Sendable (String) -> Void)?
    private var onClose: (() -> Void)?
    private var closeTimer: DispatchSourceTimer?
    private var droppedAudioBufferCount = 0
    private var decodeFailureCount = 0
    private var binaryDecodeFailureCount = 0

    init(
        onTranscriptEvent: (@Sendable (String, Bool) -> Void)? = nil,
        onLog: (@Sendable (String, LogLevel) -> Void)? = nil,
        onTranscriptionError: (@Sendable (String) -> Void)? = nil
    ) {
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        self.onTranscriptEvent = onTranscriptEvent
        self.onLog = onLog
        self.onTranscriptionError = onTranscriptionError
        super.init()
        queue.setSpecific(key: queueKey, value: ())
    }

    func connect(
        apiKey: String,
        format: AudioStreamFormat,
        language: DeepgramLanguage
    ) {
        disconnect()

        var components = URLComponents()
        components.scheme = "wss"
        components.host = "api.deepgram.com"
        components.path = "/v1/listen"

        let queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(format.sampleRate)),
            URLQueryItem(name: "channels", value: String(format.channels)),
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: language.deepgramCode),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: "100"),
            URLQueryItem(name: "smart_format", value: "true"),
        ]

        components.queryItems = queryItems

        guard let url = components.url else {
            reportTranscriptionError("Failed to build Deepgram URL.")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        queue.sync {
            self.task = task
            self.isConnected = true
            self.isClosing = false
        }
        task.resume()
        onLog?("WebSocket connecting to \(url.absoluteString)", .info)

        receiveLoop(for: task)
    }

    func sendAudio(buffer: AVAudioPCMBuffer) {
        let task = queue.sync { isConnected ? self.task : nil }
        guard let task else { return }
        guard let data = AudioBufferConverter.linear16Data(from: buffer) else {
            let dropCount = queue.sync { () -> Int in
                droppedAudioBufferCount += 1
                return droppedAudioBufferCount
            }
            if Self.shouldLogOccurrence(dropCount) {
                onLog?("Dropped audio buffer during linear16 conversion (\(dropCount) total drops).", .warning)
            }
            return
        }

        task.send(.data(data)) { [weak self] error in
            guard let self, let error else { return }
            let shouldReport = self.queue.sync {
                self.task === task && self.isConnected && !self.isClosing
            }
            if shouldReport {
                self.reportTranscriptionError("WebSocket send error: \(error.localizedDescription)")
            }
        }
    }

    func closeStream(onClosed: @escaping () -> Void) {
        let task = queue.sync { self.task }
        guard let task else {
            onClosed()
            return
        }

        queue.sync {
            isClosing = true
            isConnected = false
            onClose = onClosed
        }

        let closeMessage = "{\"type\":\"CloseStream\"}"
        task.send(.string(closeMessage)) { [weak self] error in
            if let error {
                self?.onLog?("Failed to send CloseStream: \(error.localizedDescription)", .error)
            } else {
                self?.onLog?("Sent CloseStream to Deepgram.", .info)
            }
        }

        scheduleCloseTimeout()
    }

    func disconnect() {
        let hadConnection = queue.sync { () -> Bool in
            let hadConnection = isConnected || isClosing || task != nil
            isConnected = false
            isClosing = false
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            onClose = nil
            return hadConnection
        }
        closeTimer?.cancel()
        closeTimer = nil
        if hadConnection {
            onLog?("WebSocket disconnected.", .info)
        }
    }

    private func receiveLoop(for task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            let isCurrentTask = self.queue.sync { self.task === task }
            guard isCurrentTask else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncoming(text: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncoming(text: text)
                    } else {
                        let failureCount = self.queue.sync { () -> Int in
                            self.binaryDecodeFailureCount += 1
                            return self.binaryDecodeFailureCount
                        }
                        if Self.shouldLogOccurrence(failureCount) {
                            self.onLog?(
                                "Received non-UTF8 Deepgram data frame (\(data.count) bytes, \(failureCount) decode failures).",
                                .warning
                            )
                        }
                    }
                @unknown default:
                    break
                }
            case .failure(let error):
                let state = self.queue.sync { () -> (wasClosing: Bool, isCurrent: Bool) in
                    guard self.task === task else {
                        return (false, false)
                    }
                    self.isConnected = false
                    return (self.isClosing, true)
                }
                guard state.isCurrent else { return }

                if state.wasClosing {
                    self.finishClose()
                } else {
                    self.reportTranscriptionError("WebSocket receive error: \(error.localizedDescription)")
                }
                return
            }

            let shouldContinue = self.queue.sync {
                self.task === task && self.isConnected
            }
            if shouldContinue {
                self.receiveLoop(for: task)
            }
        }
    }

    private func handleIncoming(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        guard let result = try? JSONDecoder().decode(DeepgramLiveResult.self, from: data) else {
            let failureCount = queue.sync { () -> Int in
                decodeFailureCount += 1
                return decodeFailureCount
            }
            if Self.shouldLogOccurrence(failureCount) {
                onLog?(
                    "Failed to decode Deepgram message (\(failureCount) failures). Preview: \(Self.preview(text))",
                    .warning
                )
            }
            return
        }

        if let transcript = result.transcript, !transcript.isEmpty {
            let isFinal = (result.is_final ?? false) || (result.speech_final ?? false) || (result.from_finalize ?? false)
            onTranscriptEvent?(transcript, isFinal)
        }

        if result.type == "Error", let description = result.errorDescription {
            reportTranscriptionError("Deepgram error: \(description)")
        }
    }

    private func scheduleCloseTimeout() {
        closeTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0)
        timer.setEventHandler { [weak self] in
            self?.finishClose()
        }
        closeTimer = timer
        timer.activate()
    }

    private func finishClose() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            finishCloseOnQueue()
        } else {
            queue.async { [weak self] in
                self?.finishCloseOnQueue()
            }
        }
    }

    private func finishCloseOnQueue() {
        guard isClosing else { return }
        isClosing = false
        let callback = onClose
        onClose = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        closeTimer?.cancel()
        closeTimer = nil
        onLog?("WebSocket closed after CloseStream.", .info)
        callback?()
    }

    private func reportTranscriptionError(_ message: String) {
        onLog?(message, .error)
        onTranscriptionError?(message)
    }

    private static func shouldLogOccurrence(_ occurrence: Int) -> Bool {
        occurrence <= 3 || occurrence % 100 == 0
    }

    private static func preview(_ text: String, maxLength: Int = 180) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ").trimmed
        guard normalized.count > maxLength else { return normalized }
        return String(normalized.prefix(maxLength)) + "…"
    }
}

private struct DeepgramLiveResult: Decodable {
    let type: String?
    let channel: DeepgramChannel?
    let is_final: Bool?
    let speech_final: Bool?
    let from_finalize: Bool?
    let errorDescription: String?

    var transcript: String? {
        channel?.alternatives?.first?.transcript
    }

    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case is_final
        case speech_final
        case from_finalize
        case errorDescription = "description"
    }
}

private struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]?
}

private struct DeepgramAlternative: Decodable {
    let transcript: String?
}
