import XCTest
@testable import TalkieCore

@MainActor
final class AppStateTests: XCTestCase {
    private let apiKeyDefaultsKey = "Talkie.ApiKey"
    private let languageDefaultsKey = "Talkie.DeepgramLanguage"
    private let starredLanguagesDefaultsKey = "Talkie.StarredDeepgramLanguages"
    private let shortcutsDefaultsKey = "Talkie.Shortcuts"
    private let escToCancelDefaultsKey = "Talkie.EscToCancelRecording"
    private let playSoundEffectsDefaultsKey = "Talkie.PlaySoundEffects"
    private let restoreClipboardAfterPasteDefaultsKey = "Talkie.RestoreClipboardAfterPaste"
    private let audioInputSelectionDefaultsKey = "Talkie.AudioInputSelection"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: languageDefaultsKey)
        UserDefaults.standard.removeObject(forKey: starredLanguagesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: escToCancelDefaultsKey)
        UserDefaults.standard.removeObject(forKey: playSoundEffectsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: restoreClipboardAfterPasteDefaultsKey)
        UserDefaults.standard.removeObject(forKey: audioInputSelectionDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: languageDefaultsKey)
        UserDefaults.standard.removeObject(forKey: starredLanguagesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: escToCancelDefaultsKey)
        UserDefaults.standard.removeObject(forKey: playSoundEffectsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: restoreClipboardAfterPasteDefaultsKey)
        UserDefaults.standard.removeObject(forKey: audioInputSelectionDefaultsKey)
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

    func testFinalizeLatestInterimTranscriptPromotesLastTranscript() {
        let state = AppState()
        state.resetTranscript()

        state.handleTranscript("this is interim", isFinal: false)
        state.finalizeLatestInterimTranscript()

        XCTAssertEqual(state.finalTranscript, "this is interim")
    }

    func testFinalizeLatestInterimTranscriptAvoidsDuplicateSegment() {
        let state = AppState()
        state.resetTranscript()

        state.handleTranscript("segment", isFinal: true)
        state.handleTranscript("segment", isFinal: false)
        state.finalizeLatestInterimTranscript()

        XCTAssertEqual(state.finalTranscript, "segment")
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

    func testStarredDeepgramLanguagesDefaultToAutomaticAndEnglish() {
        let state = AppState()
        XCTAssertEqual(state.starredDeepgramLanguages, [.automatic, .english])
    }

    func testStarredDeepgramLanguagesPersistDeduplicatedValues() {
        let state = AppState()
        state.starredDeepgramLanguages = [.french, .english, .french]

        let restored = AppState()
        XCTAssertEqual(restored.starredDeepgramLanguages, [.french, .english])
    }

    func testStarredDeepgramLanguagesIgnoreInvalidStoredValues() {
        UserDefaults.standard.set(
            [DeepgramLanguage.french.rawValue, "invalid-language", DeepgramLanguage.english.rawValue, DeepgramLanguage.french.rawValue],
            forKey: starredLanguagesDefaultsKey
        )

        let state = AppState()
        XCTAssertEqual(state.starredDeepgramLanguages, [.french, .english])
    }

    func testStarredDeepgramLanguagesMigrationKeepsCurrentLanguage() {
        UserDefaults.standard.set(DeepgramLanguage.french.rawValue, forKey: languageDefaultsKey)
        UserDefaults.standard.removeObject(forKey: starredLanguagesDefaultsKey)

        let state = AppState()
        XCTAssertEqual(state.deepgramLanguage, .french)
        XCTAssertEqual(state.starredDeepgramLanguages, [.automatic, .english])
    }

    func testStarredDeepgramLanguagesCannotBecomeEmpty() {
        let state = AppState()
        state.starredDeepgramLanguages = [.english]
        state.starredDeepgramLanguages = []

        XCTAssertEqual(state.starredDeepgramLanguages, [.english])
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
        state.shortcuts.append(ShortcutConfig(id: UUID(), key: .leftControl, mode: .click))

        let restored = AppState()
        XCTAssertEqual(restored.shortcuts.count, 2)
        XCTAssertEqual(restored.shortcuts[0].id, id)
        XCTAssertEqual(restored.shortcuts[0].key, .fn)
        XCTAssertEqual(restored.shortcuts[0].mode, .hold)
        XCTAssertEqual(restored.shortcuts[1].key, .leftControl)
        XCTAssertEqual(restored.shortcuts[1].mode, .click)
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

    // MARK: - Clipboard Restore

    func testRestoreClipboardAfterPasteDefaultsToFalse() {
        let state = AppState()
        XCTAssertFalse(state.restoreClipboardAfterPaste)
    }

    func testRestoreClipboardAfterPastePersists() {
        let state = AppState()
        state.restoreClipboardAfterPaste = true

        let restored = AppState()
        XCTAssertTrue(restored.restoreClipboardAfterPaste)
    }

    func testAudioInputSelectionDefaultsToSystemDefault() {
        let state = AppState()
        XCTAssertEqual(state.audioInputSelection, .systemDefault)
    }

    func testAudioInputSelectionPersistsSelectedDevice() {
        let state = AppState()
        state.audioInputSelection = .device("usb-mic-123")

        let restored = AppState()
        XCTAssertEqual(restored.audioInputSelection, .device("usb-mic-123"))
    }
}
