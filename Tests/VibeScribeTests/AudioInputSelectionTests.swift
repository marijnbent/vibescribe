import XCTest
@testable import VibeScribeCore

final class AudioInputSelectionTests: XCTestCase {
    func testStoredValueRoundTripsDeviceSelection() {
        let selection = AudioInputSelection.device("external-mic")
        XCTAssertEqual(AudioInputSelection(storedValue: selection.storedValue), selection)
    }

    func testStoredValueFallsBackToSystemDefaultForInvalidPayload() {
        XCTAssertEqual(AudioInputSelection(storedValue: "device:"), .systemDefault)
        XCTAssertEqual(AudioInputSelection(storedValue: "bogus"), .systemDefault)
    }
}
