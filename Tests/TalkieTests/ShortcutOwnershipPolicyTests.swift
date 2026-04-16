import XCTest
@testable import TalkieCore

final class ShortcutOwnershipPolicyTests: XCTestCase {
    func testIsOwner() {
        let ownerID = UUID()
        let ownership = RecordingOwnership(
            ownerShortcutID: ownerID,
            ownerMode: .both,
            isLatched: false,
            recordingStartedAt: 100,
            sessionID: UUID()
        )

        XCTAssertTrue(ShortcutOwnershipPolicy.isOwner(shortcutID: ownerID, ownership: ownership))
        XCTAssertFalse(ShortcutOwnershipPolicy.isOwner(shortcutID: UUID(), ownership: ownership))
    }

    func testShouldIgnoreOnlyNonOwnerDuringRecording() {
        let ownerID = UUID()
        let otherID = UUID()
        let ownership = RecordingOwnership(
            ownerShortcutID: ownerID,
            ownerMode: .hold,
            isLatched: false,
            recordingStartedAt: 10,
            sessionID: UUID()
        )

        XCTAssertFalse(ShortcutOwnershipPolicy.shouldIgnore(shortcutID: ownerID, isRecording: true, ownership: ownership))
        XCTAssertTrue(ShortcutOwnershipPolicy.shouldIgnore(shortcutID: otherID, isRecording: true, ownership: ownership))
        XCTAssertFalse(ShortcutOwnershipPolicy.shouldIgnore(shortcutID: otherID, isRecording: false, ownership: ownership))
        XCTAssertFalse(ShortcutOwnershipPolicy.shouldIgnore(shortcutID: otherID, isRecording: true, ownership: nil))
    }

    func testShouldIgnoreNonOwnerWhenLatchedRecording() {
        let ownerID = UUID()
        let otherID = UUID()
        let ownership = RecordingOwnership(
            ownerShortcutID: ownerID,
            ownerMode: .click,
            isLatched: true,
            recordingStartedAt: 22,
            sessionID: UUID()
        )

        XCTAssertFalse(ShortcutOwnershipPolicy.shouldIgnore(shortcutID: ownerID, isRecording: true, ownership: ownership))
        XCTAssertTrue(ShortcutOwnershipPolicy.shouldIgnore(shortcutID: otherID, isRecording: true, ownership: ownership))
    }

    func testShouldNotIgnoreWhenSessionNotRecordingEvenWithOwnership() {
        let ownerID = UUID()
        let otherID = UUID()
        let ownership = RecordingOwnership(
            ownerShortcutID: ownerID,
            ownerMode: .both,
            isLatched: false,
            recordingStartedAt: 3,
            sessionID: UUID()
        )

        XCTAssertFalse(ShortcutOwnershipPolicy.shouldIgnore(shortcutID: ownerID, isRecording: false, ownership: ownership))
        XCTAssertFalse(ShortcutOwnershipPolicy.shouldIgnore(shortcutID: otherID, isRecording: false, ownership: ownership))
    }
}
