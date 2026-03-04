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
    private let onConnectionDropped: (@Sendable (String) -> Void)?
    private var onClose: (() -> Void)?
    private var closeTimer: DispatchSourceTimer?
    private var keepAliveTimer: DispatchSourceTimer?
    private var droppedAudioBufferCount = 0
    private var decodeFailureCount = 0
    private var binaryDecodeFailureCount = 0

    // Buffered audio replay state for reconnect recovery.
    private var bufferedAudioChunks: [Data] = []
    private var bufferedChunkBaseIndex = 0
    private var nextChunkToSendIndex = 0
    private var bufferedAudioBytes = 0
    private var hasLoggedLargeBufferWarning = false
    private var bytesPerSecond = 32_000

    private let closeTimeoutSeconds: TimeInterval = 6.0
    private let keepAliveIntervalSeconds: TimeInterval = 4.0
    private let replayOverlapSeconds: TimeInterval = 3.0
    private let sentAudioRetentionSeconds: TimeInterval = 45.0
    private let largeBufferWarningBytes = 64 * 1024 * 1024

    init(
        onTranscriptEvent: (@Sendable (String, Bool) -> Void)? = nil,
        onLog: (@Sendable (String, LogLevel) -> Void)? = nil,
        onTranscriptionError: (@Sendable (String) -> Void)? = nil,
        onConnectionDropped: (@Sendable (String) -> Void)? = nil
    ) {
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        self.onTranscriptEvent = onTranscriptEvent
        self.onLog = onLog
        self.onTranscriptionError = onTranscriptionError
        self.onConnectionDropped = onConnectionDropped
        super.init()
        queue.setSpecific(key: queueKey, value: ())
    }

    func connect(
        apiKey: String,
        format: AudioStreamFormat,
        language: DeepgramLanguage
    ) {
        disconnect(preserveBufferedAudio: true, logDisconnection: false)

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
            self.bytesPerSecond = max(1, format.sampleRate * format.channels * 2)
            self.closeTimer?.cancel()
            self.closeTimer = nil
            self.startKeepAliveOnQueue(for: task)
        }
        task.resume()
        onLog?("WebSocket connecting to \(url.absoluteString)", .info)

        // If audio was buffered while disconnected, replay it as soon as the new socket is up.
        queue.async { [weak self] in
            self?.flushBufferedAudioOnQueue(for: task)
        }

        receiveLoop(for: task)
    }

    func sendAudio(buffer: AVAudioPCMBuffer) {
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

        queue.async { [weak self] in
            guard let self else { return }
            _ = self.appendBufferedChunkOnQueue(data)
            self.logLargeBufferWarningIfNeededOnQueue()

            guard let task = self.task, self.isConnected, !self.isClosing else { return }
            self.flushBufferedAudioOnQueue(for: task)
        }
    }

    func closeStream(onClosed: @escaping () -> Void) {
        let task = queue.sync { self.task }
        guard let task else {
            queue.sync {
                clearBufferedAudioOnQueue()
                onClose = nil
                isClosing = false
                isConnected = false
            }
            onClosed()
            return
        }

        queue.sync {
            isClosing = true
            isConnected = false
            onClose = onClosed
        }

        let finalizeMessage = "{\"type\":\"Finalize\"}"
        task.send(.string(finalizeMessage)) { [weak self] error in
            guard let self else { return }
            if let error {
                let shouldIgnore = self.queue.sync {
                    self.task !== task || !self.isClosing
                }
                if !shouldIgnore && !Self.isCancellationError(error) {
                    self.onLog?("Failed to send Finalize: \(error.localizedDescription)", .warning)
                }
            } else {
                let shouldLogSuccess = self.queue.sync {
                    self.task === task && self.isClosing
                }
                if shouldLogSuccess {
                    self.onLog?("Sent Finalize to Deepgram.", .info)
                }
            }
            self.sendCloseStreamMessage(on: task)
        }

        scheduleCloseTimeout()
    }

    private func sendCloseStreamMessage(on task: URLSessionWebSocketTask) {
        let closeMessage = "{\"type\":\"CloseStream\"}"
        task.send(.string(closeMessage)) { [weak self] error in
            guard let self else { return }
            if let error {
                let shouldIgnore = self.queue.sync {
                    self.task !== task || !self.isClosing
                }
                if shouldIgnore || Self.isCancellationError(error) {
                    return
                }
                self.onLog?("Failed to send CloseStream: \(error.localizedDescription)", .error)
            } else {
                let shouldLogSuccess = self.queue.sync {
                    self.task === task && self.isClosing
                }
                if shouldLogSuccess {
                    self.onLog?("Sent CloseStream to Deepgram.", .info)
                }
            }
        }
    }

    func disconnect() {
        disconnect(preserveBufferedAudio: false, logDisconnection: true)
    }

    private func disconnect(preserveBufferedAudio: Bool, logDisconnection: Bool) {
        let hadConnection = queue.sync { () -> Bool in
            let hadConnection = isConnected || isClosing || task != nil
            isConnected = false
            isClosing = false
            closeTimer?.cancel()
            closeTimer = nil
            cancelKeepAliveLocked()
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            onClose = nil
            if !preserveBufferedAudio {
                clearBufferedAudioOnQueue()
            }
            return hadConnection
        }
        if hadConnection && logDisconnection {
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
                    self.handleIncoming(text: text, for: task)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncoming(text: text, for: task)
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
                self.queue.async { [weak self] in
                    guard let self else { return }
                    guard self.task === task else { return }

                    if self.isClosing {
                        self.finishCloseOnQueue()
                        return
                    }

                    if Self.isCancellationError(error) {
                        return
                    }

                    let message = "WebSocket receive error: \(error.localizedDescription)"
                    self.handleUnexpectedConnectionDropOnQueue(message, task: task)
                }
                return
            }

            let shouldContinue = self.queue.sync {
                self.task === task && (self.isConnected || self.isClosing)
            }
            if shouldContinue {
                self.receiveLoop(for: task)
            }
        }
    }

    private func handleIncoming(text: String, for task: URLSessionWebSocketTask) {
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

        // Any valid server message implies the socket is alive, so try flushing backlog.
        queue.async { [weak self] in
            guard let self else { return }
            guard self.task === task, self.isConnected, !self.isClosing else { return }
            self.flushBufferedAudioOnQueue(for: task)
        }

        if let transcript = result.transcript, !transcript.isEmpty {
            let isFinal = (result.is_final ?? false) || (result.speech_final ?? false) || (result.from_finalize ?? false)
            onTranscriptEvent?(transcript, isFinal)
        }

        if result.type == "Error", let description = result.errorDescription {
            reportTranscriptionError("Deepgram error: \(description)")
        }

        // Deepgram can signal finalization before actively closing the socket.
        // Finish immediately when that signal arrives instead of waiting for timeout.
        let shouldFinishAfterFinalize = queue.sync {
            isClosing && ((result.from_finalize ?? false) || result.type == "Finalize")
        }
        if shouldFinishAfterFinalize {
            finishClose()
        }
    }

    private func handleUnexpectedConnectionDropOnQueue(_ message: String, task: URLSessionWebSocketTask) {
        guard self.task === task else { return }
        guard !isClosing else { return }

        isConnected = false
        self.task = nil
        cancelKeepAliveLocked()
        rewindReplayCursorOnConnectionDropOnQueue()
        reportTranscriptionError(message)
        onConnectionDropped?(message)
    }

    private func appendBufferedChunkOnQueue(_ data: Data) -> Int {
        let chunkIndex = bufferedChunkBaseIndex + bufferedAudioChunks.count
        bufferedAudioChunks.append(data)
        bufferedAudioBytes += data.count
        return chunkIndex
    }

    private func flushBufferedAudioOnQueue(for task: URLSessionWebSocketTask) {
        guard self.task === task, isConnected, !isClosing else { return }

        let endIndex = bufferedChunkBaseIndex + bufferedAudioChunks.count
        guard nextChunkToSendIndex < endIndex else {
            pruneSentAudioBufferOnQueue()
            return
        }

        let startIndex = nextChunkToSendIndex
        for chunkIndex in startIndex..<endIndex {
            guard let offset = bufferOffset(for: chunkIndex) else { continue }
            sendBufferedChunkOnQueue(bufferedAudioChunks[offset], task: task)
        }
        nextChunkToSendIndex = endIndex

        if endIndex - startIndex > 1 {
            onLog?("Replayed \(endIndex - startIndex) buffered audio chunks after reconnect.", .warning)
        }

        pruneSentAudioBufferOnQueue()
    }

    private func sendBufferedChunkOnQueue(_ chunk: Data, task: URLSessionWebSocketTask) {
        task.send(.data(chunk)) { [weak self] error in
            guard let self, let error else { return }
            guard !Self.isCancellationError(error) else { return }

            self.queue.async { [weak self] in
                guard let self else { return }
                let message = "WebSocket send error: \(error.localizedDescription)"
                self.handleUnexpectedConnectionDropOnQueue(message, task: task)
            }
        }
    }

    private func rewindReplayCursorOnConnectionDropOnQueue() {
        let lookbackBytes = max(Int(Double(bytesPerSecond) * replayOverlapSeconds), bytesPerSecond)
        let rewindIndex = indexForLookbackBytes(before: nextChunkToSendIndex, lookbackBytes: lookbackBytes)
        nextChunkToSendIndex = max(bufferedChunkBaseIndex, rewindIndex)
    }

    private func pruneSentAudioBufferOnQueue() {
        let keepBytes = max(
            Int(Double(bytesPerSecond) * sentAudioRetentionSeconds),
            Int(Double(bytesPerSecond) * replayOverlapSeconds)
        )
        let minimumIndexToKeep = indexForLookbackBytes(before: nextChunkToSendIndex, lookbackBytes: keepBytes)
        let dropCount = minimumIndexToKeep - bufferedChunkBaseIndex
        guard dropCount > 0 else { return }

        var droppedBytes = 0
        for chunk in bufferedAudioChunks.prefix(dropCount) {
            droppedBytes += chunk.count
        }

        bufferedAudioChunks.removeFirst(dropCount)
        bufferedChunkBaseIndex += dropCount
        bufferedAudioBytes = max(0, bufferedAudioBytes - droppedBytes)

        if nextChunkToSendIndex < bufferedChunkBaseIndex {
            nextChunkToSendIndex = bufferedChunkBaseIndex
        }

        if hasLoggedLargeBufferWarning && bufferedAudioBytes < largeBufferWarningBytes / 2 {
            hasLoggedLargeBufferWarning = false
        }
    }

    private func indexForLookbackBytes(before upperBoundIndex: Int, lookbackBytes: Int) -> Int {
        let upperBound = min(upperBoundIndex, bufferedChunkBaseIndex + bufferedAudioChunks.count)
        var index = upperBound
        var remaining = lookbackBytes

        while index > bufferedChunkBaseIndex, remaining > 0 {
            let offset = index - bufferedChunkBaseIndex - 1
            remaining -= bufferedAudioChunks[offset].count
            index -= 1
        }

        return index
    }

    private func bufferOffset(for chunkIndex: Int) -> Int? {
        let offset = chunkIndex - bufferedChunkBaseIndex
        guard offset >= 0, offset < bufferedAudioChunks.count else { return nil }
        return offset
    }

    private func logLargeBufferWarningIfNeededOnQueue() {
        guard bufferedAudioBytes >= largeBufferWarningBytes else { return }
        guard !hasLoggedLargeBufferWarning else { return }

        hasLoggedLargeBufferWarning = true
        let bufferedMB = Int(Double(bufferedAudioBytes) / 1_048_576)
        onLog?("Buffered reconnect audio has grown to \(bufferedMB) MB while waiting for Deepgram recovery.", .warning)
    }

    private func clearBufferedAudioOnQueue() {
        bufferedAudioChunks.removeAll(keepingCapacity: false)
        bufferedChunkBaseIndex = 0
        nextChunkToSendIndex = 0
        bufferedAudioBytes = 0
        hasLoggedLargeBufferWarning = false
    }

    private func scheduleCloseTimeout() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            scheduleCloseTimeoutOnQueue()
        } else {
            queue.async { [weak self] in
                self?.scheduleCloseTimeoutOnQueue()
            }
        }
    }

    private func scheduleCloseTimeoutOnQueue() {
        guard isClosing else { return }
        closeTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + closeTimeoutSeconds)
        timer.setEventHandler { [weak self] in
            self?.finishCloseOnQueue()
        }
        closeTimer = timer
        timer.activate()
    }

    private func startKeepAliveOnQueue(for task: URLSessionWebSocketTask) {
        cancelKeepAliveLocked()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + keepAliveIntervalSeconds, repeating: keepAliveIntervalSeconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.task === task, self.isConnected, !self.isClosing else { return }
            task.send(.string("{\"type\":\"KeepAlive\"}")) { [weak self] error in
                guard let self, let error else { return }
                let shouldLog = self.queue.sync {
                    self.task === task && self.isConnected && !self.isClosing
                }
                if shouldLog && !Self.isCancellationError(error) {
                    self.onLog?("Failed to send KeepAlive: \(error.localizedDescription)", .warning)
                }
            }
        }
        keepAliveTimer = timer
        timer.activate()
    }

    private func cancelKeepAliveLocked() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
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
        cancelKeepAliveLocked()
        clearBufferedAudioOnQueue()
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

    private static func isCancellationError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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
