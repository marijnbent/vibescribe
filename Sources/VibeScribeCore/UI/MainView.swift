import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var appState: AppState
    @State private var expandedHistoryEntries: Set<UUID> = []

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView(appState: appState)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            EnhancementsSettingsView(appState: appState)
                .tabItem { Label("Enhancements", systemImage: "wand.and.stars") }
            historyTab
                .tabItem { Label("History", systemImage: "clock") }
            logsTab
                .tabItem { Label("Logs", systemImage: "list.bullet.rectangle") }
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
                Text("Transcription")
            } footer: {
                Text("Automatic detects the spoken language.")
            }

            Section("Behavior") {
                Toggle("Cancel recording with Escape", isOn: $appState.escToCancelRecording)
                Toggle("Play sound effects", isOn: $appState.playSoundEffects)
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
        VStack(alignment: .leading, spacing: 0) {
            if appState.transcriptHistory.isEmpty {
                Text("No transcriptions yet.")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.transcriptHistory) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Self.formatter.string(from: entry.timestamp))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if entry.enhancedText != nil {
                                    historyRow(label: "Original", text: entry.text, entryID: entry.id)
                                    historyRow(label: "Enhanced", text: entry.enhancedText!, entryID: entry.id)
                                } else {
                                    historyRow(label: nil, text: entry.text, entryID: entry.id)
                                }
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Logs")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    appState.clearLogs()
                }
            }
            .padding(.horizontal)

            if appState.logs.isEmpty {
                Text("No logs yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
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
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top)
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
