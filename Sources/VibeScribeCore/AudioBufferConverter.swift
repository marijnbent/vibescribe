import AVFoundation

enum AudioBufferConverter {
    static func linear16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatChannelData = buffer.floatChannelData else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let sampleCount = frameLength * channelCount
        guard sampleCount > 0 else { return Data() }

        var int16Samples = [Int16](repeating: 0, count: sampleCount)
        int16Samples.withUnsafeMutableBufferPointer { destination in
            var index = 0
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    let sample = floatChannelData[channel][frame]
                    let clamped = max(-1.0, min(1.0, sample))
                    destination[index] = Int16(clamped * Float(Int16.max))
                    index += 1
                }
            }
        }

        return int16Samples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }
}
