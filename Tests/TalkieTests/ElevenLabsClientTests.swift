import Foundation
import XCTest
@testable import TalkieCore

final class ElevenLabsClientTests: XCTestCase {
    func testInputAudioMessageUsesElevenLabsWireKeys() throws {
        let message = try ElevenLabsClient.makeInputAudioMessage(
            audio: Data([0x01, 0x02]),
            commit: true,
            sampleRate: 48_000
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any])

        XCTAssertEqual(object["message_type"] as? String, "input_audio_chunk")
        XCTAssertEqual(object["audio_base_64"] as? String, "AQI=")
        XCTAssertEqual(object["commit"] as? Bool, true)
        XCTAssertEqual(object["sample_rate"] as? Int, 48_000)
        XCTAssertNil(object["audioBase64"])
        XCTAssertNil(object["sampleRate"])
    }

    func testDownmixPCM16AveragesInterleavedChannels() {
        // Frames: (-1000, 1000), (3000, 1000) -> 0, 2000.
        let stereo = Data([
            0x18, 0xFC, 0xE8, 0x03,
            0xB8, 0x0B, 0xE8, 0x03,
        ])

        XCTAssertEqual(
            AudioBufferConverter.monoPCM16(stereo, channels: 2),
            Data([0x00, 0x00, 0xD0, 0x07])
        )
    }

    func testRealtimeEventDecodesTranscriptAndErrorFields() throws {
        let transcript = try JSONDecoder().decode(
            ElevenLabsRealtimeEvent.self,
            from: Data(#"{"message_type":"committed_transcript","text":"hello"}"#.utf8)
        )
        XCTAssertEqual(transcript.messageType, "committed_transcript")
        XCTAssertEqual(transcript.text, "hello")

        let error = try JSONDecoder().decode(
            ElevenLabsRealtimeEvent.self,
            from: Data(#"{"message_type":"rate_limited","error":"slow down"}"#.utf8)
        )
        XCTAssertEqual(error.messageType, "rate_limited")
        XCTAssertEqual(error.error, "slow down")
    }

    func testLanguageCodeUsesISOBaseCode() {
        XCTAssertEqual(elevenLabsLanguageCode(for: .englishAmerican), "en")
        XCTAssertEqual(elevenLabsLanguageCode(for: .flemish), "nl")
        XCTAssertEqual(elevenLabsLanguageCode(for: .cantonese), "yue")
        XCTAssertEqual(elevenLabsLanguageCode(for: .chineseCantonese), "yue")
        XCTAssertEqual(elevenLabsLanguageCode(for: .mandarinChinese), "zho")
        XCTAssertEqual(elevenLabsLanguageCode(for: .tagalog), "fil")
        XCTAssertNil(elevenLabsLanguageCode(for: .automatic))
    }

    func testAutomaticLanguageQueryRestrictsDetectionToDutchAndEnglish() {
        let items = ElevenLabsClient.languageQueryItems(for: .automatic)

        XCTAssertEqual(items.map(\.name), ["secondary_languages", "secondary_languages"])
        XCTAssertEqual(items.map(\.value), ["nl", "en"])
    }

    func testAutomaticLanguageQueryUsesConfiguredCandidates() {
        let items = ElevenLabsClient.languageQueryItems(
            for: .automatic,
            automaticLanguageCandidates: [.german, .french, .russian]
        )

        XCTAssertEqual(items.map(\.name), ["secondary_languages", "secondary_languages", "secondary_languages"])
        XCTAssertEqual(items.map(\.value), ["fr", "de", "ru"])
    }

    func testExplicitLanguageQueryDoesNotAddAutomaticCandidates() {
        let items = ElevenLabsClient.languageQueryItems(for: .english)

        XCTAssertEqual(items.map(\.name), ["language_code"])
        XCTAssertEqual(items.map(\.value), ["en"])
    }
}
