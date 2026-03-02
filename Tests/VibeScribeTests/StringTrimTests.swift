import XCTest
@testable import VibeScribeCore

final class StringTrimTests: XCTestCase {
    func testTrimmedRemovesWhitespaceAndNewlines() {
        XCTAssertEqual("  hello\n".trimmed, "hello")
    }

}
