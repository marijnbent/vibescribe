import AVFoundation
import Foundation

struct Linear16AudioChunk: Sendable, Equatable {
    let data: Data
    let meterLevel: Float
}

enum AudioBufferConverter {
    static func linear16Chunk(from buffer: AVAudioPCMBuffer) -> Linear16AudioChunk? {
        guard let floatChannelData = buffer.floatChannelData else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let sampleCount = frameLength * channelCount
        guard sampleCount > 0 else {
            return Linear16AudioChunk(data: Data(), meterLevel: 0)
        }

        var data = Data(count: sampleCount * MemoryLayout<Int16>.size)
        var firstChannelSquareSum: Float = 0
        data.withUnsafeMutableBytes { rawBuffer in
            let destination = rawBuffer.bindMemory(to: Int16.self)
            var index = 0
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    let sample = floatChannelData[channel][frame]
                    if channel == 0 {
                        firstChannelSquareSum += sample * sample
                    }
                    let clamped = max(-1.0, min(1.0, sample))
                    destination[index] = Int16(clamped * Float(Int16.max))
                    index += 1
                }
            }
        }

        let rootMeanSquare = sqrt(firstChannelSquareSum / Float(frameLength))
        let meterLevel = min(1, sqrt(rootMeanSquare) * 3.5)
        return Linear16AudioChunk(data: data, meterLevel: meterLevel)
    }

    static func monoPCM16(_ data: Data, channels: Int) -> Data {
        guard channels > 0 else { return Data() }
        guard channels > 1 else { return data }
        let frameCount = data.count / MemoryLayout<Int16>.size / channels
        var result = Data(count: frameCount * MemoryLayout<Int16>.size)
        result.withUnsafeMutableBytes { destination in
            let output = destination.bindMemory(to: Int16.self)
            data.withUnsafeBytes { source in
                if channels == 2 {
                    for frame in 0..<frameCount {
                        let left = Int16(littleEndian: source.loadUnaligned(fromByteOffset: frame * 4, as: Int16.self))
                        let right = Int16(littleEndian: source.loadUnaligned(fromByteOffset: frame * 4 + 2, as: Int16.self))
                        output[frame] = Int16((Int(left) + Int(right)) / 2).littleEndian
                    }
                    return
                }
                for frame in 0..<frameCount {
                    var sum = 0
                    for channel in 0..<channels {
                        let offset = (frame * channels + channel) * MemoryLayout<Int16>.size
                        sum += Int(Int16(littleEndian: source.loadUnaligned(fromByteOffset: offset, as: Int16.self)))
                    }
                    output[frame] = Int16(sum / channels).littleEndian
                }
            }
        }
        return result
    }
}
