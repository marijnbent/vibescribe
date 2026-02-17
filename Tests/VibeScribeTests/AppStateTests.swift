import XCTest
@testable import VibeScribeCore

@MainActor
final class AppStateTests: XCTestCase {
    private let apiKeyDefaultsKey = "VibeScribe.ApiKey"
    private let languageDefaultsKey = "VibeScribe.DeepgramLanguage"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: languageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: languageDefaultsKey)
        super.tearDown()
    }

    func testHandleTranscriptBuildsFinalTranscript() {
        let state = AppState()
        state.resetTranscript()

        state.handleTranscript(" hello ", isFinal: true)
        XCTAssertEqual(state.finalTranscript, "hello")

        state.handleTranscript("hello", isFinal: true)
        XCTAssertEqual(state.finalTranscript, "hello")

        state.handleTranscript("world", isFinal: true)
        XCTAssertEqual(state.finalTranscript, "hello world")
    }

    func testHandleTranscriptIgnoresEmptyFinalText() {
        let state = AppState()
        state.resetTranscript()

        state.handleTranscript(" ", isFinal: true)
        XCTAssertEqual(state.finalTranscript, "")
    }

    func testNonFinalTranscriptUpdatesLastOnly() {
        let state = AppState()
        state.resetTranscript()

        state.handleTranscript("partial", isFinal: false)
        XCTAssertEqual(state.lastTranscript, "partial")
        XCTAssertEqual(state.finalTranscript, "")
    }

    func testResetTranscriptClearsState() {
        let state = AppState()
        state.handleTranscript("hello", isFinal: true)

        state.resetTranscript()
        XCTAssertEqual(state.lastTranscript, "")
        XCTAssertEqual(state.finalTranscript, "")
    }

    func testDeepgramLanguageDefaultsToAutomatic() {
        let state = AppState()
        XCTAssertEqual(state.deepgramLanguage, .automatic)
    }

    func testDeepgramLanguagePersists() {
        let state = AppState()
        state.deepgramLanguage = .french

        let restored = AppState()
        XCTAssertEqual(restored.deepgramLanguage, .french)
    }
}
