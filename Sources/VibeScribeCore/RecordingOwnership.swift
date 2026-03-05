import Foundation

struct RecordingOwnership {
    let ownerShortcutID: UUID
    let ownerMode: ShortcutMode
    var isLatched: Bool
    let recordingStartedAt: TimeInterval
    let sessionID: UUID
}
