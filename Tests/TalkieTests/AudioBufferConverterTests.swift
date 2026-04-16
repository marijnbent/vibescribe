import AVFoundation
import XCTest
@testable import TalkieCore

final class AudioBufferConverterTests: XCTestCase {
    func testLinear16DataConvertsFloatSamples() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3)!
        buffer.frameLength = 3

        let channel = buffer.floatChannelData![0]
        channel[0] = -1.0
        channel[1] = 0.0
        channel[2] = 1.0

        guard let data = AudioBufferConverter.linear16Data(from: buffer) else {
            return XCTFail("Expected linear16 data for float buffer.")
        }

        let values = data.withUnsafeBytes { bufferPointer -> [Int16] in
            Array(bufferPointer.bindMemory(to: Int16.self))
        }

        XCTAssertEqual(values, [-32767, 0, 32767])
    }

    func testLinear16DataClampsOutOfRangeSamples() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2

        let channel = buffer.floatChannelData![0]
        channel[0] = 2.0
        channel[1] = -2.0

        guard let data = AudioBufferConverter.linear16Data(from: buffer) else {
            return XCTFail("Expected linear16 data for float buffer.")
        }

        let values = data.withUnsafeBytes { bufferPointer -> [Int16] in
            Array(bufferPointer.bindMemory(to: Int16.self))
        }

        XCTAssertEqual(values, [32767, -32767])
    }
}
