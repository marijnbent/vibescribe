import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel
    @State private var languageSearchText = ""

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent {
                    Button(viewModel.microphonePermissionButtonTitle()) {
                        viewModel.requestMicrophonePermission()
                    }
                    .disabled(viewModel.microphonePermission.isGranted)
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
                    Button(viewModel.accessibilityPermissionButtonTitle()) {
                        viewModel.requestAccessibilityPermission()
                    }
                    .disabled(viewModel.accessibilityPermission.isGranted)
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
                Picker("Microphone", selection: viewModel.binding(for: \.audioInputSelection)) {
                    Text(viewModel.resolvedAudioInputSelection.systemDefaultDevice.map {
                        "System Default (\($0.name))"
                    } ?? "System Default")
                        .tag(AudioInputSelection.systemDefault)

                    ForEach(viewModel.availableAudioInputs) { input in
                        Text(input.name).tag(AudioInputSelection.device(input.id))
                    }
                }
            } header: {
                Text("Recording")
            } footer: {
                Text(viewModel.audioInputHelpText)
            }

            Section {
                SecureField("API Key", text: viewModel.binding(for: \.apiKey))
                Picker("Current language", selection: viewModel.binding(for: \.deepgramLanguage)) {
                    ForEach(DeepgramLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            } header: {
                Text("Deepgram")
            } footer: {
                Text("Automatic detects the spoken language.")
            }

            Section {
                TextField("Search languages", text: $languageSearchText)
                    .textFieldStyle(.roundedBorder)

                if viewModel.menuBarLanguages(matching: languageSearchText).isEmpty {
                    Text("No languages found")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.menuBarLanguages(matching: languageSearchText)) { language in
                                MenuBarLanguageSettingsRow(
                                    language: language,
                                    isCurrent: viewModel.deepgramLanguage == language,
                                    isStarred: viewModel.isLanguageStarred(language),
                                    canToggleStarRemoval: viewModel.canToggleStarRemoval(for: language),
                                    onToggleStar: { viewModel.toggleStar(for: language) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160, maxHeight: 220)
                }
            } header: {
                Text("Menu bar languages")
            } footer: {
                Text("Only starred languages appear in the menu bar language submenu.")
            }

            Section("Behavior") {
                Toggle("Cancel recording with Escape", isOn: viewModel.binding(for: \.escToCancelRecording))
                Toggle("Play sound effects", isOn: viewModel.binding(for: \.playSoundEffects))
                Toggle("Mute during recording", isOn: viewModel.binding(for: \.muteMediaDuringRecording))
                Toggle("Restore clipboard after confirmed auto-paste", isOn: viewModel.binding(for: \.restoreClipboardAfterPaste))
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

private struct MenuBarLanguageSettingsRow: View {
    let language: DeepgramLanguage
    let isCurrent: Bool
    let isStarred: Bool
    let canToggleStarRemoval: Bool
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.displayName)

                if isCurrent {
                    Text("Current selection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onToggleStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isStarred && !canToggleStarRemoval)
            .accessibilityLabel(isStarred ? "Remove star" : "Add star")
            .help(isStarred ? "Remove from menu bar languages" : "Add to menu bar languages")
        }
    }
}
