import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, shortcuts, enhancements, history, logs, about

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    var label: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .enhancements: "Enhancements"
        case .history: "History"
        case .logs: "Logs"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .enhancements: "wand.and.stars"
        case .history: "clock"
        case .logs: "list.bullet.rectangle"
        case .about: "info.circle"
        }
    }
}

struct MainView: View {
    @ObservedObject var appState: AppState
    @State private var expandedHistoryEntries: Set<UUID> = []

    var body: some View {
        Group {
            switch appState.selectedTab {
            case .general: generalTab
            case .shortcuts: ShortcutsSettingsView(appState: appState)
            case .enhancements: EnhancementsSettingsView(appState: appState)
            case .history: historyTab
            case .logs: logsTab
            case .about: aboutTab
            }
        }
        .frame(minWidth: 680, minHeight: 560)
    }

    private var generalTab: some View {
        Form {
            Section("Permissions") {
                LabeledContent {
                    Button("Request") {
                        appState.requestMicrophonePermission()
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recording")
                            Text(appState.microphonePermission.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Circle()
                            .fill(appState.microphonePermission.color)
                            .frame(width: 8, height: 8)
                    }
                }

                LabeledContent {
                    Button("Request") {
                        appState.requestAccessibilityPermission()
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pasting")
                            Text(appState.accessibilityPermission.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Circle()
                            .fill(appState.accessibilityPermission.color)
                            .frame(width: 8, height: 8)
                    }
                }
            }

            Section {
                SecureField("API Key", text: $appState.apiKey)
                Picker("Language", selection: $appState.deepgramLanguage) {
                    ForEach(DeepgramLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            } header: {
                Text("Deepgram")
            } footer: {
                Text("Automatic detects the spoken language.")
            }

            Section("Behavior") {
                Toggle("Cancel recording with Escape", isOn: $appState.escToCancelRecording)
                Toggle("Play sound effects", isOn: $appState.playSoundEffects)
                Toggle("Pause media during recording", isOn: $appState.pauseMediaDuringRecording)
            }

            Section("History") {
                Picker("Keep history", selection: $appState.historyLimit) {
                    ForEach(HistoryLimit.allCases) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshPermissions()
        }
    }

    private var historyTab: some View {
        Form {
            if appState.transcriptHistory.isEmpty {
                Section {
                    Text("No transcriptions yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(appState.transcriptHistory) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Self.formatter.string(from: entry.timestamp))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            if entry.enhancedText != nil {
                                historyRow(label: "Original", text: entry.text, entryID: entry.id)
                                historyRow(label: "Enhanced", text: entry.enhancedText!, entryID: entry.id)
                            } else {
                                historyRow(label: nil, text: entry.text, entryID: entry.id)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var logsTab: some View {
        Form {
            if appState.logs.isEmpty {
                Section {
                    Text("No logs yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(appState.logs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(Self.formatter.string(from: entry.timestamp)) \(entry.level.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    copyLogEntry(entry)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .help("Copy log entry")
                            }
                            Text(entry.message)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    HStack {
                        Spacer()
                        Button("Clear") {
                            appState.clearLogs()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("VibeScribe")
                .font(.title)
                .fontWeight(.semibold)
            Text("Voice-to-text for macOS")
                .foregroundStyle(.secondary)
            Link("GitHub", destination: URL(string: "https://github.com/nicktmro/vibescribe")!)
                .foregroundStyle(.tint)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func historyRow(label: String?, text: String, entryID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                if let label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Copy \(label?.lowercased() ?? "transcript")")
            }
            Text(text)
                .lineLimit(expandedHistoryEntries.contains(entryID) ? nil : 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedHistoryEntries.contains(entryID) {
                            expandedHistoryEntries.remove(entryID)
                        } else {
                            expandedHistoryEntries.insert(entryID)
                        }
                    }
                }
        }
    }

    private func copyLogEntry(_ entry: LogEntry) {
        let text = "\(Self.formatter.string(from: entry.timestamp)) \(entry.level.rawValue) \(entry.message)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private extension MainView {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
