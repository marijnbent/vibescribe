import XCTest
@testable import VibeScribeCore

final class StringTrimTests: XCTestCase {
    func testTrimmedRemovesWhitespaceAndNewlines() {
        XCTAssertEqual("  hello\n".trimmed, "hello")
    }

    func testNilIfEmptyReturnsNilForWhitespace() {
        XCTAssertNil("   \n\t  ".nilIfEmpty)
    }

    func testNilIfEmptyReturnsTrimmedString() {
        XCTAssertEqual("  hi  ".nilIfEmpty, "hi")
    }
}
