import Foundation

enum ShortcutOwnershipPolicy {
    static func isOwner(shortcutID: UUID, ownership: RecordingOwnership?) -> Bool {
        ownership?.ownerShortcutID == shortcutID
    }

    static func shouldIgnore(shortcutID: UUID, isRecording: Bool, ownership: RecordingOwnership?) -> Bool {
        guard isRecording, let ownership else { return false }
        return ownership.ownerShortcutID != shortcutID
    }
}
