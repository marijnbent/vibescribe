import AppKit
import Foundation
import SwiftUI

@MainActor
final class SessionState: ObservableObject {
    static let maxLogEntries = 1_000

    private let historyStore: TranscriptHistoryStore?

    @Published var recordingPhase: RecordingPhase = .idle
    @Published var appStatus: AppStatus = .idle
    @Published var lastTranscript = ""
    @Published var finalTranscript = ""
    @Published var logs: [LogEntry] = []
    @Published var transcriptHistory: [TranscriptHistoryEntry] = [] {
        didSet {
            historyStore?.saveEntries(transcriptHistory)
        }
    }
    @Published var overlayPulseID = UUID()
    @Published var overlayVisible = false
    @Published var overlayLabel = "Listening"
    @Published var overlayAppIcon: NSImage?
    @Published var audioLevel: CGFloat = 0
    var onHistoryEntriesRemoved: (([TranscriptHistoryEntry]) -> Void)?

    var isRecording: Bool {
        recordingPhase == .recording
    }

    var statusMessage: String {
        appStatus.message
    }

    private var transcriptSegments: [String] = []

    init(
        historyStore: TranscriptHistoryStore? = nil,
        initialTranscriptHistory: [TranscriptHistoryEntry] = []
    ) {
        self.historyStore = historyStore
        self.transcriptHistory = initialTranscriptHistory
    }

    func resetTranscript() {
        lastTranscript = ""
        finalTranscript = ""
        transcriptSegments.removeAll()
    }

    func handleTranscript(_ text: String, isFinal: Bool) {
        lastTranscript = text
        guard isFinal else { return }
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        if transcriptSegments.last != trimmed {
            transcriptSegments.append(trimmed)
            finalTranscript = transcriptSegments.joined(separator: " ")
        }
    }

    func finalizeLatestInterimTranscript() {
        let trimmed = lastTranscript.trimmed
        guard !trimmed.isEmpty else { return }
        if transcriptSegments.last != trimmed {
            transcriptSegments.append(trimmed)
            finalTranscript = transcriptSegments.joined(separator: " ")
        }
    }

    func addLog(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(timestamp: Date(), level: level, message: message))
        if logs.count > Self.maxLogEntries {
            logs.removeFirst(logs.count - Self.maxLogEntries)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func storeTranscriptHistoryEntry(_ entry: TranscriptHistoryEntry, limit: HistoryLimit) {
        guard limit != .none else {
            onHistoryEntriesRemoved?([entry])
            return
        }
        transcriptHistory.insert(entry, at: 0)
        applyHistoryLimit(limit)
    }

    func addTranscriptToHistory(
        _ text: String,
        enhancedText: String? = nil,
        transcriptionError: String? = nil,
        enhancementError: String? = nil,
        promptName: String? = nil,
        enhancementPromptText: String? = nil,
        rawRecordingFileURL: URL? = nil,
        transcriptionLanguage: DeepgramLanguage? = nil,
        usedActiveAppPrompt: Bool = false,
        limit: HistoryLimit
    ) {
        guard limit != .none else {
            let discardedEntry = TranscriptHistoryEntry(
                timestamp: Date(),
                text: text,
                enhancedText: enhancedText,
                transcriptionError: transcriptionError,
                enhancementError: enhancementError,
                promptName: promptName,
                enhancementPromptText: enhancementPromptText,
                rawRecordingFileURL: rawRecordingFileURL,
                transcriptionLanguage: transcriptionLanguage,
                usedActiveAppPrompt: usedActiveAppPrompt
            )
            onHistoryEntriesRemoved?([discardedEntry])
            return
        }
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: text,
            enhancedText: enhancedText,
            transcriptionError: transcriptionError,
            enhancementError: enhancementError,
            promptName: promptName,
            enhancementPromptText: enhancementPromptText,
            rawRecordingFileURL: rawRecordingFileURL,
            transcriptionLanguage: transcriptionLanguage,
            usedActiveAppPrompt: usedActiveAppPrompt
        )
        storeTranscriptHistoryEntry(entry, limit: limit)
    }

    func addTranscriptionFailureToHistory(reason: String, partialText: String = "", limit: HistoryLimit) {
        addTranscriptToHistory(
            partialText,
            transcriptionError: reason,
            limit: limit
        )
    }

    func applyHistoryLimit(_ limit: HistoryLimit) {
        let max = limit.rawValue
        if max == 0 {
            let removedEntries = transcriptHistory
            transcriptHistory.removeAll()
            if !removedEntries.isEmpty {
                onHistoryEntriesRemoved?(removedEntries)
            }
        } else if transcriptHistory.count > max {
            let removedEntries = Array(transcriptHistory.suffix(transcriptHistory.count - max))
            transcriptHistory.removeLast(transcriptHistory.count - max)
            if !removedEntries.isEmpty {
                onHistoryEntriesRemoved?(removedEntries)
            }
        }
    }

    func updateTranscriptHistoryEntry(
        id: UUID,
        transform: (TranscriptHistoryEntry) -> TranscriptHistoryEntry
    ) {
        guard let index = transcriptHistory.firstIndex(where: { $0.id == id }) else { return }
        transcriptHistory[index] = transform(transcriptHistory[index])
    }
}

struct TranscriptHistoryEntry: Codable, Identifiable {
    static let emptyTranscriptionMessage = "No speech was detected or no final transcript was returned."

    let id: UUID
    let timestamp: Date
    let text: String
    let enhancedText: String?
    let transcriptionError: String?
    let enhancementError: String?
    let promptName: String?
    let enhancementPromptText: String?
    let rawRecordingFileURL: URL?
    let transcriptionLanguage: DeepgramLanguage?
    let usedActiveAppPrompt: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date,
        text: String,
        enhancedText: String? = nil,
        transcriptionError: String? = nil,
        enhancementError: String? = nil,
        promptName: String? = nil,
        enhancementPromptText: String? = nil,
        rawRecordingFileURL: URL? = nil,
        transcriptionLanguage: DeepgramLanguage? = nil,
        usedActiveAppPrompt: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.enhancedText = enhancedText
        self.transcriptionError = transcriptionError
        self.enhancementError = enhancementError
        self.promptName = promptName
        self.enhancementPromptText = enhancementPromptText
        self.rawRecordingFileURL = rawRecordingFileURL
        self.transcriptionLanguage = transcriptionLanguage
        self.usedActiveAppPrompt = usedActiveAppPrompt
    }

    var displayText: String {
        let source = (enhancedText ?? text).trimmed
        if source.isEmpty {
            if let transcriptionError {
                return "Transcription failed: \(transcriptionError)"
            }
            if let enhancementError {
                return "Enhancement failed: \(enhancementError)"
            }
            return ""
        }
        let sentences = source.splitIntoSentences()
        if sentences.count <= 3 { return source }
        return sentences.prefix(3).joined() + "…"
    }

    var shouldShowTranscriptionWarningIcon: Bool {
        guard let transcriptionError else { return false }
        return !(text.trimmed.isEmpty && transcriptionError == Self.emptyTranscriptionMessage)
    }

    var promptSourceLabel: String {
        usedActiveAppPrompt ? "Active app" : "Default"
    }

    var savedEnhancementPromptLabel: String? {
        enhancementPromptText?
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .first(where: { !$0.isEmpty })
    }

    var canRetryEnhancement: Bool {
        !text.trimmed.isEmpty &&
        (enhancedText?.trimmed ?? "").isEmpty &&
        !(enhancementPromptText?.trimmed ?? "").isEmpty
    }

    var canRetryTranscription: Bool {
        rawRecordingFileURL != nil &&
        transcriptionLanguage != nil &&
        (transcriptionError != nil || text.trimmed.isEmpty)
    }
}

extension String {
    func splitIntoSentences() -> [String] {
        var sentences: [String] = []
        enumerateSubstrings(in: startIndex..., options: .bySentences) { _, range, _, _ in
            sentences.append(String(self[range]))
        }
        return sentences
    }
}
