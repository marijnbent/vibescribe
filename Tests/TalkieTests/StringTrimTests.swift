import XCTest
@testable import TalkieCore

final class StringTrimTests: XCTestCase {
    func testTrimmedRemovesWhitespaceAndNewlines() {
        XCTAssertEqual("  hello\n".trimmed, "hello")
    }

}
