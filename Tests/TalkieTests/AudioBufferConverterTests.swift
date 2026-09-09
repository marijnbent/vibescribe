import AVFoundation
import XCTest
@testable import TalkieCore

final class AudioBufferConverterTests: XCTestCase {
    func testCaptureConvertsInterleavedInt16WithoutChangingFramesOrChannels() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        ))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        input.frameLength = 2
        let values: [Int16] = [-16_384, 8_192, 0, 16_384]
        for (index, value) in values.enumerated() {
            input.int16ChannelData![0][index] = value
        }
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = 4
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        XCTAssertEqual(CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format.formatDescription,
            sampleCount: 2,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ), noErr)
        let sample = try XCTUnwrap(sampleBuffer)
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(
            sample,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: input.audioBufferList
        ), noErr)

        let output = try XCTUnwrap(AudioCaptureController.pcmBuffer(from: sample))
        XCTAssertEqual(output.frameLength, 2)
        XCTAssertEqual(output.format.sampleRate, 48_000)
        XCTAssertEqual(output.format.channelCount, 2)
        XCTAssertFalse(output.format.isInterleaved)
        XCTAssertEqual(output.floatChannelData![0][0], -0.5, accuracy: 0.0001)
        XCTAssertEqual(output.floatChannelData![0][1], 0, accuracy: 0.0001)
        XCTAssertEqual(output.floatChannelData![1][0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(output.floatChannelData![1][1], 0.5, accuracy: 0.0001)
    }

    func testMonoPCM16HandlesUnalignedSlicesAndIncompleteFrames() {
        let bytes = Data([255, 0, 128, 255, 127, 255, 127, 255, 127, 12])
        XCTAssertEqual(
            AudioBufferConverter.monoPCM16(bytes.dropFirst(), channels: 2),
            Data([0, 0, 255, 127])
        )
        XCTAssertEqual(AudioBufferConverter.monoPCM16(Data(), channels: 2), Data())
        XCTAssertEqual(AudioBufferConverter.monoPCM16(bytes, channels: 1), bytes)
    }

    func testLinear16ChunkConvertsFloatSamplesAndCalculatesMeterLevel() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3)!
        buffer.frameLength = 3

        let channel = buffer.floatChannelData![0]
        channel[0] = -1.0
        channel[1] = 0.0
        channel[2] = 1.0

        guard let chunk = AudioBufferConverter.linear16Chunk(from: buffer) else {
            return XCTFail("Expected a linear16 chunk for the float buffer.")
        }

        let values = chunk.data.withUnsafeBytes { bufferPointer -> [Int16] in
            Array(bufferPointer.bindMemory(to: Int16.self))
        }

        XCTAssertEqual(values, [-32767, 0, 32767])
        XCTAssertGreaterThan(chunk.meterLevel, 0)
        XCTAssertLessThanOrEqual(chunk.meterLevel, 1)
    }

    func testLinear16ChunkClampsOutOfRangeSamples() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2

        let channel = buffer.floatChannelData![0]
        channel[0] = 2.0
        channel[1] = -2.0

        guard let chunk = AudioBufferConverter.linear16Chunk(from: buffer) else {
            return XCTFail("Expected a linear16 chunk for the float buffer.")
        }

        let values = chunk.data.withUnsafeBytes { bufferPointer -> [Int16] in
            Array(bufferPointer.bindMemory(to: Int16.self))
        }

        XCTAssertEqual(values, [32767, -32767])
    }
}
