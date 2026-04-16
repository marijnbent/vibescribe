import AVFoundation
import Foundation

protocol RawRecordingCapture {
    func append(buffer: AVAudioPCMBuffer)
    func finish() throws -> URL?
    func discard()
}

final class RawRecordingStore {
    private let fileManager: FileManager
    private let baseDirectory: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        let resolvedBaseDirectory = baseDirectory ?? Self.defaultBaseDirectory(fileManager: fileManager)
        self.baseDirectory = resolvedBaseDirectory
        prepareBaseDirectory()
    }

    func makeCapture(format: AudioStreamFormat) -> RawRecordingCapture {
        FileRawRecordingCapture(
            format: format,
            fileManager: fileManager,
            baseDirectory: baseDirectory
        )
    }

    func deleteRecording(at url: URL?) {
        guard let url else { return }
        let standardizedBase = baseDirectory.standardizedFileURL.path
        let standardizedTarget = url.standardizedFileURL.path
        guard standardizedTarget.hasPrefix(standardizedBase) else { return }
        try? fileManager.removeItem(at: url)
    }

    func pruneRecordings(keeping urls: [URL]) {
        let allowedPaths = Set(
            urls.map { $0.standardizedFileURL.path }
        )

        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents {
            let path = url.standardizedFileURL.path
            if !allowedPaths.contains(path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func prepareBaseDirectory() {
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    private static func defaultBaseDirectory(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root.appendingPathComponent("Talkie/HistoryAudio", isDirectory: true)
    }
}

private final class FileRawRecordingCapture: RawRecordingCapture {
    private let format: AudioStreamFormat
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let lock = NSLock()

    private var chunks: [Data] = []
    private var isFinished = false

    init(format: AudioStreamFormat, fileManager: FileManager, baseDirectory: URL) {
        self.format = format
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func append(buffer: AVAudioPCMBuffer) {
        guard let data = AudioBufferConverter.linear16Data(from: buffer), !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        chunks.append(data)
    }

    func finish() throws -> URL? {
        let audioData: Data = lock.withLock {
            guard !isFinished else { return Data() }
            isFinished = true

            let totalBytes = chunks.reduce(0) { $0 + $1.count }
            var combined = Data()
            combined.reserveCapacity(totalBytes)
            for chunk in chunks {
                combined.append(chunk)
            }
            chunks.removeAll(keepingCapacity: false)
            return combined
        }

        guard !audioData.isEmpty else { return nil }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let url = baseDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        try Self.wavData(
            wrapping: audioData,
            sampleRate: format.sampleRate,
            channels: format.channels
        ).write(to: url, options: .atomic)
        return url
    }

    func discard() {
        lock.withLock {
            isFinished = true
            chunks.removeAll(keepingCapacity: false)
        }
    }

    private static func wavData(
        wrapping pcmData: Data,
        sampleRate: Int,
        channels: Int
    ) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let riffChunkSize = 36 + pcmData.count

        var data = Data()
        data.reserveCapacity(44 + pcmData.count)
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(riffChunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.appendLE(UInt32(pcmData.count))
        data.append(pcmData)
        return data
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { rawBuffer in
            append(contentsOf: rawBuffer)
        }
    }
}
