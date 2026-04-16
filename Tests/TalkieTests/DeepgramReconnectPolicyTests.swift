import XCTest
@testable import TalkieCore

final class DeepgramReconnectPolicyTests: XCTestCase {
    func testAllowsExactlyOneReconnectAttempt() {
        XCTAssertTrue(DeepgramReconnectPolicy.shouldRetry(currentAttempt: 0))
        XCTAssertFalse(DeepgramReconnectPolicy.shouldRetry(currentAttempt: 1))
        XCTAssertFalse(DeepgramReconnectPolicy.shouldRetry(currentAttempt: 2))
    }
}
