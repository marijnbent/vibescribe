import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        Form {
            if viewModel.transcriptHistory.isEmpty {
                Section {
                    Text("No transcriptions yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.transcriptHistory) { entry in
                    Section {
                        if let transcriptionError = entry.transcriptionError {
                            issueRow(
                                label: "Transcription error",
                                message: transcriptionError,
                                showsIcon: entry.shouldShowTranscriptionWarningIcon
                            )
                        }

                        if let enhancementError = entry.enhancementError {
                            issueRow(label: "Enhancement error", message: enhancementError)
                        }

                        if let savedPromptLabel = entry.savedEnhancementPromptLabel {
                            LabeledContent("Saved prompt") {
                                Text(savedPromptLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let promptName = entry.promptName {
                            LabeledContent("Prompt name") {
                                Text(promptName)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if entry.promptName != nil || entry.savedEnhancementPromptLabel != nil {
                            LabeledContent("Prompt source") {
                                Text(entry.promptSourceLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        let original = entry.text.trimmed
                        let enhanced = entry.enhancedText?.trimmed ?? ""
                        if !original.isEmpty, !enhanced.isEmpty {
                            historyRow(label: "Original", text: original, entryID: entry.id)
                            historyRow(label: "Enhanced", text: enhanced, entryID: entry.id)
                        } else if !enhanced.isEmpty {
                            historyRow(label: "Enhanced", text: enhanced, entryID: entry.id)
                        } else if !original.isEmpty {
                            historyRow(label: nil, text: original, entryID: entry.id)
                        }

                        if entry.canRetryTranscription || entry.canRetryEnhancement {
                            retryActionsRow(entry)
                        }
                    } header: {
                        Text(MainView.formatter.string(from: entry.timestamp))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func historyRow(label: String?, text: String, entryID: UUID) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let label {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .lineLimit(viewModel.isExpanded(entryID) ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleExpansion(entryID)
                        }
                    }
            }

            Button {
                viewModel.copy(text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Copy \(label?.lowercased() ?? "transcript")")
        }
    }

    private func issueRow(label: String, message: String, showsIcon: Bool = true) -> some View {
        HStack(alignment: .top, spacing: showsIcon ? 6 : 0) {
            if showsIcon {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(message)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func retryActionsRow(_ entry: TranscriptHistoryEntry) -> some View {
        HStack(spacing: 8) {
            if entry.canRetryTranscription {
                Button {
                    viewModel.retryTranscription(for: entry)
                } label: {
                    Image(systemName: "waveform")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.isRetrying(entry.id))
                .help("Retry transcription and enhancement from saved recording")
            }

            if entry.canRetryEnhancement {
                Button {
                    viewModel.retryEnhancement(for: entry)
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.isRetrying(entry.id))
                .help("Retry enhancement")
            }

            if viewModel.isRetrying(entry.id) {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
