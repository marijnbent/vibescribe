import XCTest
@testable import VibeScribeCore

@MainActor
final class AppStateTests: XCTestCase {
    private let apiKeyDefaultsKey = "VibeScribe.ApiKey"
    private let languageDefaultsKey = "VibeScribe.DeepgramLanguage"
    private let shortcutsDefaultsKey = "VibeScribe.Shortcuts"
    private let escToCancelDefaultsKey = "VibeScribe.EscToCancelRecording"
    private let playSoundEffectsDefaultsKey = "VibeScribe.PlaySoundEffects"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: languageDefaultsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: escToCancelDefaultsKey)
        UserDefaults.standard.removeObject(forKey: playSoundEffectsDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: languageDefaultsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: escToCancelDefaultsKey)
        UserDefaults.standard.removeObject(forKey: playSoundEffectsDefaultsKey)
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

    // MARK: - Shortcuts Persistence

    func testShortcutsDefaultToSingleRightOptionBoth() {
        let state = AppState()
        XCTAssertEqual(state.shortcuts.count, 1)
        XCTAssertEqual(state.shortcuts[0].key, .rightOption)
        XCTAssertEqual(state.shortcuts[0].mode, .both)
    }

    func testShortcutsPersist() {
        let state = AppState()
        let id = state.shortcuts[0].id
        state.shortcuts[0].key = .fn
        state.shortcuts[0].mode = .hold
        state.shortcuts.append(ShortcutConfig(id: UUID(), key: .leftControl, mode: .doubleClick))

        let restored = AppState()
        XCTAssertEqual(restored.shortcuts.count, 2)
        XCTAssertEqual(restored.shortcuts[0].id, id)
        XCTAssertEqual(restored.shortcuts[0].key, .fn)
        XCTAssertEqual(restored.shortcuts[0].mode, .hold)
        XCTAssertEqual(restored.shortcuts[1].key, .leftControl)
        XCTAssertEqual(restored.shortcuts[1].mode, .doubleClick)
    }

    func testShortcutsEmptyArrayFallsBackToDefault() {
        // Manually store an empty array
        let data = try! JSONEncoder().encode([ShortcutConfig]())
        UserDefaults.standard.set(data, forKey: shortcutsDefaultsKey)

        let state = AppState()
        XCTAssertEqual(state.shortcuts.count, 1, "Empty persisted array should fall back to default")
        XCTAssertEqual(state.shortcuts[0].key, .rightOption)
    }

    func testShortcutsCorruptedDataFallsBackToDefault() {
        UserDefaults.standard.set(Data([0xFF, 0xFE]), forKey: shortcutsDefaultsKey)

        let state = AppState()
        XCTAssertEqual(state.shortcuts.count, 1)
        XCTAssertEqual(state.shortcuts[0].key, .rightOption)
    }

    // MARK: - ESC to Cancel Recording

    func testEscToCancelRecordingDefaultsToTrue() {
        let state = AppState()
        XCTAssertTrue(state.escToCancelRecording)
    }

    func testEscToCancelRecordingPersists() {
        let state = AppState()
        state.escToCancelRecording = false

        let restored = AppState()
        XCTAssertFalse(restored.escToCancelRecording)
    }

    // MARK: - Sound Effects

    func testPlaySoundEffectsDefaultsToFalse() {
        let state = AppState()
        XCTAssertFalse(state.playSoundEffects)
    }

    func testPlaySoundEffectsPersists() {
        let state = AppState()
        state.playSoundEffects = true

        let restored = AppState()
        XCTAssertTrue(restored.playSoundEffects)
    }
}
