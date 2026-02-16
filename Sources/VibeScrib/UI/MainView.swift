import SwiftUI

struct MainView: View {
    @ObservedObject var appState: AppState
    let onToggleRecording: () -> Void

    var body: some View {
        TabView {
            homeTab
                .tabItem { Text("Home") }
            logsTab
                .tabItem { Text("Logs") }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }

    private var homeTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            statusSection
            Divider()
            settingsSection
            transcriptSection
            Spacer()
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
                        ForEach(appState.logs) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Self.formatter.string(from: entry.timestamp)) \(entry.level.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VibeScrib")
                .font(.system(size: 28, weight: .semibold))
            Text("Push-to-talk transcription powered by Deepgram")
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        HStack(spacing: 16) {
            RecordingBadge(isRecording: appState.isRecording)
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.headline)
                Text(appState.statusMessage)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                onToggleRecording()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Push-to-Talk") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hotkey")
                        .font(.subheadline)
                    Text(appState.hotkey.displayName)
                        .foregroundStyle(.secondary)
                    Text("Change this in code for now (Hotkey.pushToTalkDefault).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Deepgram") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("API Key", text: $appState.apiKey)
                    Text("Using Deepgram Nova 3 with multilingual code-switching (language=multi).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var transcriptSection: some View {
        GroupBox("Latest Transcript") {
            ScrollView {
                Text(transcriptText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
        }
    }

    private var transcriptText: String {
        if !appState.finalTranscript.isEmpty {
            return appState.finalTranscript
        }
        if !appState.lastTranscript.isEmpty {
            return appState.lastTranscript
        }
        return "Waiting for transcription..."
    }
}

private struct RecordingBadge: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: 56, height: 56)
            Circle()
                .fill(isRecording ? Color.red : Color.gray)
                .frame(width: 16, height: 16)
        }
        .accessibilityLabel(isRecording ? "Recording" : "Not recording")
    }
}

private extension MainView {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
