import AVFoundation

enum AudioBufferConverter {
    static func linear16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatChannelData = buffer.floatChannelData else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var data = Data(capacity: frameLength * channelCount * MemoryLayout<Int16>.size)

        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = floatChannelData[channel][frame]
                let clamped = max(-1.0, min(1.0, sample))
                var int16 = Int16(clamped * Float(Int16.max))
                withUnsafeBytes(of: &int16) { rawBuffer in
                    data.append(contentsOf: rawBuffer)
                }
            }
        }

        return data
    }
}
