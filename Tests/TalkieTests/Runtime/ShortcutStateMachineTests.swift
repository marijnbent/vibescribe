import XCTest
@testable import TalkieCore

final class ShortcutStateMachineTests: XCTestCase {
    private let threshold: TimeInterval = 0.2

    func testClickModeOwnerStopsAndNonOwnerIgnored() {
        let machine = ShortcutStateMachine(clickHoldThreshold: threshold)
        let ownerID = UUID()
        let otherID = UUID()
        let ownership = RecordingOwnership(
            ownerShortcutID: ownerID,
            ownerMode: .click,
            isLatched: true,
            recordingStartedAt: 10,
            sessionID: UUID()
        )

        let startActions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyDown,
            shortcutID: ownerID,
            mode: .click,
            phase: .idle,
            ownership: nil,
            elapsedSinceStart: 0
        ))
        XCTAssertEqual(startActions, [.start(ownerShortcutID: ownerID, ownerMode: .click, latched: true)])

        let ignoredActions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyDown,
            shortcutID: otherID,
            mode: .click,
            phase: .recording,
            ownership: ownership,
            elapsedSinceStart: 0.1
        ))
        XCTAssertEqual(ignoredActions, [.noop])

        let stopActions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyDown,
            shortcutID: ownerID,
            mode: .click,
            phase: .recording,
            ownership: ownership,
            elapsedSinceStart: 0.4
        ))
        XCTAssertEqual(stopActions, [.stop])
    }

    func testBothModeQuickTapLatchesAndSecondPressStops() {
        let machine = ShortcutStateMachine(clickHoldThreshold: threshold)
        let ownerID = UUID()

        let startActions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyDown,
            shortcutID: ownerID,
            mode: .both,
            phase: .idle,
            ownership: nil,
            elapsedSinceStart: 0
        ))
        XCTAssertEqual(startActions, [.start(ownerShortcutID: ownerID, ownerMode: .both, latched: false)])

        let ownership = RecordingOwnership(
            ownerShortcutID: ownerID,
            ownerMode: .both,
            isLatched: false,
            recordingStartedAt: 5,
            sessionID: UUID()
        )

        let latchActions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyUp,
            shortcutID: ownerID,
            mode: .both,
            phase: .recording,
            ownership: ownership,
            elapsedSinceStart: 0.05
        ))
        XCTAssertEqual(latchActions, [.setLatched(true)])

        let latchedOwnership = RecordingOwnership(
            ownerShortcutID: ownerID,
            ownerMode: .both,
            isLatched: true,
            recordingStartedAt: 5,
            sessionID: UUID()
        )
        let stopActions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyDown,
            shortcutID: ownerID,
            mode: .both,
            phase: .recording,
            ownership: latchedOwnership,
            elapsedSinceStart: 1.0
        ))
        XCTAssertEqual(stopActions, [.setLatched(false), .stop])
    }

    func testHoldModeShortPressCancelsLongPressStops() {
        let machine = ShortcutStateMachine(clickHoldThreshold: threshold)
        let ownerID = UUID()
        let ownership = RecordingOwnership(
            ownerShortcutID: ownerID,
            ownerMode: .hold,
            isLatched: false,
            recordingStartedAt: 2,
            sessionID: UUID()
        )

        let cancelActions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyUp,
            shortcutID: ownerID,
            mode: .hold,
            phase: .recording,
            ownership: ownership,
            elapsedSinceStart: 0.05
        ))
        XCTAssertEqual(cancelActions, [.cancel])

        let scheduleStopActions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyUp,
            shortcutID: ownerID,
            mode: .hold,
            phase: .recording,
            ownership: ownership,
            elapsedSinceStart: 0.5
        ))
        XCTAssertEqual(scheduleStopActions, [.scheduleStop])
    }

    func testFinalizingIgnoresAllShortcutInput() {
        let machine = ShortcutStateMachine(clickHoldThreshold: threshold)
        let actions = machine.reduce(input: ShortcutStateInput(
            eventType: .keyDown,
            shortcutID: UUID(),
            mode: .click,
            phase: .finalizing,
            ownership: nil,
            elapsedSinceStart: 0
        ))
        XCTAssertEqual(actions, [.noop])
    }
}
