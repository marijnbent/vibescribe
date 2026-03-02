import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var appState: AppState
    @State private var expandedHistoryEntries: Set<UUID> = []

    var body: some View {
        TabView {
            homeTab
                .tabItem { Label("Home", systemImage: "house") }
            ShortcutsSettingsView(appState: appState)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            EnhancementsSettingsView(appState: appState)
                .tabItem { Label("Enhance", systemImage: "wand.and.stars") }
            historyTab
                .tabItem { Label("History", systemImage: "clock") }
            logsTab
                .tabItem { Label("Logs", systemImage: "list.bullet.rectangle") }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 560)
    }

    private var homeTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                permissionsSection
                Divider()
                settingsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            appState.refreshPermissions()
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

            if appState.logs.isEmpty {
                Text("No logs yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
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
                    .padding(.trailing, 8)
                }
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript History")
                    .font(.headline)
                Spacer()
                Picker("Keep", selection: $appState.historyLimit) {
                    ForEach(HistoryLimit.allCases) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
                .frame(width: 160)
            }

            if appState.transcriptHistory.isEmpty {
                Text("No transcriptions yet.")
                    .foregroundStyle(.secondary)
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
                    .padding(.trailing, 8)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VibeScribe")
                .font(.system(size: 28, weight: .semibold))
            Text("Push-to-talk transcription powered by Deepgram")
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)
            PermissionRow(
                title: "Recording",
                status: appState.microphonePermission,
                actionTitle: "Request"
            ) {
                appState.requestMicrophonePermission()
            }
            PermissionRow(
                title: "Pasting",
                status: appState.accessibilityPermission,
                actionTitle: "Request"
            ) {
                appState.requestAccessibilityPermission()
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription")
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                TextField("API Key", text: $appState.apiKey)
                Picker("Language", selection: $appState.deepgramLanguage) {
                    ForEach(DeepgramLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Text("Automatic uses Deepgram multilingual mode (language=multi).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Cancel recording with Escape key", isOn: $appState.escToCancelRecording)
                Toggle("Play sound effects", isOn: $appState.playSoundEffects)
            }
            .textFieldStyle(.roundedBorder)
        }
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

private struct PermissionRow: View {
    let title: String
    let status: PermissionStatus
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle) {
                action()
            }
        }
    }
}

private extension MainView {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
