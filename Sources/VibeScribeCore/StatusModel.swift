import Foundation

enum RecordingPhase: String, Equatable {
    case idle
    case recording
    case finalizing
}

enum AppStatus: Equatable {
    case idle
    case listening
    case finalizing
    case enhancing
    case cancelled
    case missingAPIKey
    case transcriptionIssueDetected
    case connectionRecovering
    case connectionLostReleaseToFinalize
    case transcriptionFailed
    case enhancementFailedPastingOriginal
    case enhancementSkippedMissing(String)
    case audioInputChangedReady
    case inputChangedReady
    case failedToStartAudioCapture(String)

    var message: String {
        switch self {
        case .idle:
            return "Idle"
        case .listening:
            return "Listening..."
        case .finalizing:
            return "Finalizing..."
        case .enhancing:
            return "Enhancing..."
        case .cancelled:
            return "Cancelled."
        case .missingAPIKey:
            return "Add a Deepgram API key in Settings."
        case .transcriptionIssueDetected:
            return "Transcription issue detected."
        case .connectionRecovering:
            return "Connection hiccup. Recovering..."
        case .connectionLostReleaseToFinalize:
            return "Connection lost. Release hotkey to finalize."
        case .transcriptionFailed:
            return "Transcription failed."
        case .enhancementFailedPastingOriginal:
            return "Enhancement failed. Pasting original."
        case .enhancementSkippedMissing(let missing):
            return "Enhancement skipped: missing \(missing)."
        case .audioInputChangedReady:
            return "Audio input changed. Ready."
        case .inputChangedReady:
            return "Input changed. Ready."
        case .failedToStartAudioCapture(let description):
            return "Failed to start audio capture: \(description)"
        }
    }
}
