import Foundation
import XCTest
@testable import VibeScribeCore

final class PasteVerificationMatcherTests: XCTestCase {
    func testExpectedResultInsertsAtCaret() {
        let result = PasteVerificationMatcher.expectedResult(
            initialValue: "hello world",
            selectedRange: NSRange(location: 5, length: 0),
            insertedText: ", brave"
        )

        XCTAssertEqual(result?.value, "hello, brave world")
        XCTAssertEqual(result?.selectedRange, NSRange(location: 12, length: 0))
    }

    func testExpectedResultReplacesSelection() {
        let result = PasteVerificationMatcher.expectedResult(
            initialValue: "hello world",
            selectedRange: NSRange(location: 6, length: 5),
            insertedText: "team"
        )

        XCTAssertEqual(result?.value, "hello team")
        XCTAssertEqual(result?.selectedRange, NSRange(location: 10, length: 0))
    }

    func testExpectedResultHandlesEmptyOriginalText() {
        let result = PasteVerificationMatcher.expectedResult(
            initialValue: "",
            selectedRange: NSRange(location: 0, length: 0),
            insertedText: "hello"
        )

        XCTAssertEqual(result?.value, "hello")
        XCTAssertEqual(result?.selectedRange, NSRange(location: 5, length: 0))
    }

    func testExpectedResultHandlesEmojiUsingUTF16Offsets() {
        let result = PasteVerificationMatcher.expectedResult(
            initialValue: "A🙂B",
            selectedRange: NSRange(location: 1, length: 2),
            insertedText: "rocket🚀"
        )

        XCTAssertEqual(result?.value, "Arocket🚀B")
        XCTAssertEqual(result?.selectedRange, NSRange(location: 9, length: 0))
    }

    func testExpectedResultPlacesCaretAtEndOfInsertedText() {
        let result = PasteVerificationMatcher.expectedResult(
            initialValue: "abcdef",
            selectedRange: NSRange(location: 2, length: 2),
            insertedText: "XYZ"
        )

        XCTAssertEqual(result?.selectedRange, NSRange(location: 5, length: 0))
    }

    func testExpectedResultReturnsNilForOutOfBoundsSelection() {
        let result = PasteVerificationMatcher.expectedResult(
            initialValue: "hello",
            selectedRange: NSRange(location: 10, length: 0),
            insertedText: "world"
        )

        XCTAssertNil(result)
    }

    func testExpectedResultReturnsNilForNotFoundSelection() {
        let result = PasteVerificationMatcher.expectedResult(
            initialValue: "hello",
            selectedRange: NSRange(location: NSNotFound, length: 0),
            insertedText: "world"
        )

        XCTAssertNil(result)
    }
}
