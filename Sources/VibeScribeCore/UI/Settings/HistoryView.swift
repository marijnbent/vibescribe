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

                        if let promptName = entry.promptName {
                            LabeledContent(promptName) {
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
}
