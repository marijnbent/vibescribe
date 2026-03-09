import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent {
                    Button("Request") {
                        viewModel.requestMicrophonePermission()
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recording")
                            Text(viewModel.microphonePermission.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Circle()
                            .fill(viewModel.microphonePermission.color)
                            .frame(width: 8, height: 8)
                    }
                }

                LabeledContent {
                    Button("Request") {
                        viewModel.requestAccessibilityPermission()
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pasting")
                            Text(viewModel.accessibilityPermission.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Circle()
                            .fill(viewModel.accessibilityPermission.color)
                            .frame(width: 8, height: 8)
                    }
                }
            }

            Section {
                SecureField("API Key", text: viewModel.binding(for: \.apiKey))
                Picker("Language", selection: viewModel.binding(for: \.deepgramLanguage)) {
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
                Toggle("Cancel recording with Escape", isOn: viewModel.binding(for: \.escToCancelRecording))
                Toggle("Play sound effects", isOn: viewModel.binding(for: \.playSoundEffects))
                Toggle("Mute during recording", isOn: viewModel.binding(for: \.muteMediaDuringRecording))
                Toggle("Restore clipboard after auto-paste", isOn: viewModel.binding(for: \.restoreClipboardAfterPaste))
                Picker("Widget position", selection: viewModel.binding(for: \.overlayPosition)) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
            }

            Section("History") {
                Picker("Keep history", selection: viewModel.binding(for: \.historyLimit)) {
                    ForEach(HistoryLimit.allCases) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            viewModel.refreshPermissions()
        }
    }
}
