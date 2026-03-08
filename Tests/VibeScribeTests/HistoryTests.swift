import XCTest
@testable import VibeScribeCore

@MainActor
final class HistoryTests: XCTestCase {
    private let historyLimitKey = "VibeScribe.HistoryLimit"

    override func setUp() {
        super.setUp()
        // Set to 10 (the default) rather than removing, because integer(forKey:)
        // returns 0 for missing keys, which maps to HistoryLimit.none.
        UserDefaults.standard.set(HistoryLimit.ten.rawValue, forKey: historyLimitKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: historyLimitKey)
        super.tearDown()
    }

    // MARK: - Adding Entries

    func testAddTranscriptInsertsAtFront() {
        let state = AppState()
        state.addTranscriptToHistory("first")
        state.addTranscriptToHistory("second")

        XCTAssertEqual(state.transcriptHistory.count, 2)
        XCTAssertEqual(state.transcriptHistory[0].text, "second")
        XCTAssertEqual(state.transcriptHistory[1].text, "first")
    }

    func testAddTranscriptSetsTimestamp() {
        let state = AppState()
        let before = Date()
        state.addTranscriptToHistory("test")
        let after = Date()

        let entry = state.transcriptHistory.first
        XCTAssertNotNil(entry)
        XCTAssertGreaterThanOrEqual(entry!.timestamp, before)
        XCTAssertLessThanOrEqual(entry!.timestamp, after)
    }

    func testAddTranscriptGeneratesUniqueIDs() {
        let state = AppState()
        state.addTranscriptToHistory("a")
        state.addTranscriptToHistory("b")

        let ids = state.transcriptHistory.map(\.id)
        XCTAssertEqual(Set(ids).count, 2)
    }

    // MARK: - History Limit

    func testHistoryLimitDefaultsToTen() {
        let state = AppState()
        XCTAssertEqual(state.historyLimit, .ten)
    }

    func testHistoryLimitNonePreventsAdding() {
        let state = AppState()
        state.historyLimit = .none

        state.addTranscriptToHistory("should not appear")
        XCTAssertTrue(state.transcriptHistory.isEmpty)
    }

    func testHistoryLimitTenTrimsExcess() {
        let state = AppState()
        state.historyLimit = .ten

        for i in 0..<15 {
            state.addTranscriptToHistory("entry \(i)")
        }

        XCTAssertEqual(state.transcriptHistory.count, 10)
        // Most recent should be first
        XCTAssertEqual(state.transcriptHistory[0].text, "entry 14")
    }

    func testHistoryLimitHundredAllowsMoreEntries() {
        let state = AppState()
        state.historyLimit = .hundred

        for i in 0..<50 {
            state.addTranscriptToHistory("entry \(i)")
        }

        XCTAssertEqual(state.transcriptHistory.count, 50)
    }

    func testChangingLimitToNoneClearsHistory() {
        let state = AppState()
        state.historyLimit = .ten
        state.addTranscriptToHistory("a")
        state.addTranscriptToHistory("b")
        XCTAssertEqual(state.transcriptHistory.count, 2)

        state.historyLimit = .none
        XCTAssertTrue(state.transcriptHistory.isEmpty)
    }

    func testReducingLimitTrimsExistingEntries() {
        let state = AppState()
        state.historyLimit = .hundred

        for i in 0..<20 {
            state.addTranscriptToHistory("entry \(i)")
        }
        XCTAssertEqual(state.transcriptHistory.count, 20)

        state.historyLimit = .ten
        XCTAssertEqual(state.transcriptHistory.count, 10)
        // Most recent entries should be kept
        XCTAssertEqual(state.transcriptHistory[0].text, "entry 19")
    }

    func testHistoryLimitPersists() {
        let state = AppState()
        state.historyLimit = .hundred

        let restored = AppState()
        XCTAssertEqual(restored.historyLimit, .hundred)
    }

    // MARK: - Display Text

    func testDisplayTextShortTranscript() {
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "Hello world.")
        XCTAssertEqual(entry.displayText, "Hello world.")
    }

    func testDisplayTextThreeSentencesShownInFull() {
        let text = "First sentence. Second sentence. Third sentence."
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: text)
        XCTAssertEqual(entry.displayText, text)
    }

    func testDisplayTextMoreThanThreeSentencesTruncates() {
        let text = "One. Two. Three. Four. Five."
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: text)
        XCTAssertTrue(entry.displayText.hasSuffix("…"))
        XCTAssertFalse(entry.displayText.contains("Four"))
    }

    // MARK: - Enhanced Text

    func testAddTranscriptWithEnhancedText() {
        let state = AppState()
        state.addTranscriptToHistory("raw text", enhancedText: "enhanced text")

        XCTAssertEqual(state.transcriptHistory.count, 1)
        XCTAssertEqual(state.transcriptHistory[0].text, "raw text")
        XCTAssertEqual(state.transcriptHistory[0].enhancedText, "enhanced text")
    }

    func testAddTranscriptWithoutEnhancedText() {
        let state = AppState()
        state.addTranscriptToHistory("raw text")

        XCTAssertEqual(state.transcriptHistory.count, 1)
        XCTAssertEqual(state.transcriptHistory[0].text, "raw text")
        XCTAssertNil(state.transcriptHistory[0].enhancedText)
    }

    func testAddTranscriptStoresPromptMetadata() {
        let state = AppState()
        state.addTranscriptToHistory(
            "raw text",
            promptName: "Clean up",
            usedActiveAppPrompt: true
        )

        XCTAssertEqual(state.transcriptHistory[0].promptName, "Clean up")
        XCTAssertTrue(state.transcriptHistory[0].usedActiveAppPrompt)
        XCTAssertEqual(state.transcriptHistory[0].promptSourceLabel, "Active app")
    }

    func testDisplayTextPrefersEnhancedText() {
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "raw", enhancedText: "enhanced")
        XCTAssertEqual(entry.displayText, "enhanced")
    }

    func testDisplayTextFallsBackToRawWhenNoEnhancement() {
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "raw only")
        XCTAssertEqual(entry.displayText, "raw only")
    }

    func testDisplayTextTruncatesEnhancedText() {
        let enhanced = "One. Two. Three. Four. Five."
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "raw", enhancedText: enhanced)
        XCTAssertTrue(entry.displayText.hasSuffix("…"))
        XCTAssertFalse(entry.displayText.contains("Four"))
    }

    func testEmptyTranscriptionNoticeHidesWarningIcon() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "",
            transcriptionError: TranscriptHistoryEntry.emptyTranscriptionMessage
        )
        XCTAssertFalse(entry.shouldShowTranscriptionWarningIcon)
    }

    func testTranscriptionErrorShowsWarningIcon() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "",
            transcriptionError: "WebSocket receive error."
        )
        XCTAssertTrue(entry.shouldShowTranscriptionWarningIcon)
    }

    // MARK: - HistoryLimit Enum

    func testHistoryLimitDisplayNames() {
        XCTAssertEqual(HistoryLimit.none.displayName, "None")
        XCTAssertEqual(HistoryLimit.ten.displayName, "10")
        XCTAssertEqual(HistoryLimit.hundred.displayName, "100")
    }

    func testHistoryLimitRawValues() {
        XCTAssertEqual(HistoryLimit.none.rawValue, 0)
        XCTAssertEqual(HistoryLimit.ten.rawValue, 10)
        XCTAssertEqual(HistoryLimit.hundred.rawValue, 100)
    }

    func testHistoryLimitAllCases() {
        XCTAssertEqual(HistoryLimit.allCases.count, 3)
    }
}
