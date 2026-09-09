import Foundation
import XCTest
@testable import TalkieCore

final class MuseClientTests: XCTestCase {
    func testHandshakeUsesFirstFrameAuthenticationAndDutchBias() throws {
        let text = try MuseClient.makeHandshake(
            apiKey: "test-key",
            audioEncoding: "PCM_24KHZ",
            language: .dutch
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let authorization = try XCTUnwrap(object["authorization"] as? [String: String])

        XCTAssertEqual(authorization["accessToken"], "Bearer test-key")
        XCTAssertEqual(object["audioEncoding"] as? String, "PCM_24KHZ")
        XCTAssertEqual(object["model"] as? String, "muse-voice-transcribe-1.0")
        XCTAssertEqual(object["mode"] as? String, "PUSH_TO_TALK")
        XCTAssertEqual(object["partialMode"] as? String, "CUMULATIVE")
        XCTAssertEqual(object["emitAudioProgress"] as? Bool, false)
        XCTAssertEqual(object["languageBias"] as? [String], ["Dutch"])
    }

    func testAutomaticLanguageUsesSelectedBiases() throws {
        let text = try MuseClient.makeHandshake(
            apiKey: "test-key",
            audioEncoding: "PCM_16KHZ",
            language: .automatic,
            automaticLanguageCandidates: [.dutch, .english]
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["languageBias"] as? [String], ["Dutch", "English"])
    }

    func testServerMessagesDecodeHandshakeTranscriptAndError() throws {
        let decoder = JSONDecoder()
        let handshake = try decoder.decode(
            MuseServerMessage.self,
            from: Data("{\"sessionId\":\"session-1\"}".utf8)
        )
        let transcript = try decoder.decode(
            MuseServerMessage.self,
            from: Data("{\"type\":\"transcript\",\"transcript\":\"Hallo\",\"final\":true}".utf8)
        )
        let error = try decoder.decode(
            MuseServerMessage.self,
            from: Data("{\"type\":\"error\",\"message\":\"Invalid request\"}".utf8)
        )

        XCTAssertEqual(handshake.sessionId, "session-1")
        XCTAssertEqual(transcript.transcript, "Hallo")
        XCTAssertEqual(transcript.final, true)
        XCTAssertEqual(error.message, "Invalid request")
    }

    func testConverterDownmixesAndResamplesAcrossChunks() {
        let frames: [Int16] = (0..<480).flatMap { frame in
            [Int16(frame), Int16(frame + 2)]
        }
        let data = frames.withUnsafeBufferPointer { Data(buffer: $0) }

        let complete = MusePCMConverter(
            format: AudioStreamFormat(sampleRate: 48_000, channels: 2)
        )
        var completeOutput = complete.convert(data)
        completeOutput.append(complete.finish())

        let chunked = MusePCMConverter(
            format: AudioStreamFormat(sampleRate: 48_000, channels: 2)
        )
        let midpoint = data.count / 2
        var chunkedOutput = chunked.convert(Data(data[..<midpoint]))
        chunkedOutput.append(chunked.convert(Data(data[midpoint...])))
        chunkedOutput.append(chunked.finish())

        XCTAssertEqual(complete.audioEncoding, "PCM_24KHZ")
        XCTAssertEqual(completeOutput.count, 240 * MemoryLayout<Int16>.size)
        XCTAssertEqual(chunkedOutput, completeOutput)
    }

    func testConverterRetainsOnlyTheNeededSampleAcrossSingleFrameChunks() {
        for sourceRate in [12_000, 16_000, 24_000, 48_000, 96_000] {
            let frames: [Int16] = (0..<48).flatMap { frame -> [Int16] in
                let sample = Int16(frame * 100)
                return [sample, sample + 2]
            }
            let data = frames.withUnsafeBufferPointer { Data(buffer: $0) }
            let format = AudioStreamFormat(sampleRate: sourceRate, channels: 2)
            let complete = MusePCMConverter(format: format)
            var expected = complete.convert(data)
            expected.append(complete.finish())

            let chunked = MusePCMConverter(format: format)
            var actual = Data()
            for offset in stride(from: 0, to: data.count, by: 4) {
                actual.append(chunked.convert(data[offset..<(offset + 4)]))
                actual.append(chunked.convert(Data()))
            }
            actual.append(chunked.finish())
            XCTAssertEqual(actual, expected, "Source rate: \(sourceRate)")
            XCTAssertEqual(chunked.finish(), Data())
        }
    }

    func testConverterPassesThroughCompleteMonoSamples() {
        let converter = MusePCMConverter(format: AudioStreamFormat(sampleRate: 24_000, channels: 1))
        XCTAssertEqual(converter.convert(Data([0, 128, 255, 127, 42])), Data([0, 128, 255, 127]))
        XCTAssertEqual(converter.finish(), Data())
    }
}
