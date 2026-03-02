import SwiftUI

private struct PromptRow: View {
    @Binding var prompt: PromptConfig
    var onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(prompt.name.isEmpty ? "Untitled" : prompt.name)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove prompt")
            }

            if isExpanded {
                TextField("Name", text: $prompt.name)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $prompt.content)
                    .font(.caption)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }
        }
    }
}

struct EnhancementsSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                SecureField("API Key", text: $appState.openRouterApiKey)
                TextField("Model", text: $appState.openRouterModel)
            } header: {
                Text("OpenRouter")
            } footer: {
                Text("Enter your OpenRouter API key and model identifier (e.g. google/gemini-2.5-flash-lite or openai/gpt-5-nano).")
            }

            Section {
                ForEach($appState.shortcuts) { $shortcut in
                    Picker(shortcut.key.displayName, selection: $shortcut.promptID) {
                        Text("None").tag(UUID?.none)
                        ForEach(appState.prompts) { prompt in
                            Text(prompt.name).tag(UUID?.some(prompt.id))
                        }
                    }
                }
            } header: {
                Text("Shortcut Prompts")
            } footer: {
                Text("Assign a prompt to each shortcut. The transcription is sent to OpenRouter with the selected prompt.")
            }

            Section {
                if appState.prompts.isEmpty {
                    Text("No prompts configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($appState.prompts) { $prompt in
                        PromptRow(prompt: $prompt, onDelete: {
                            appState.deletePrompt(id: prompt.id)
                        })
                    }
                }
            } header: {
                HStack {
                    Text("Prompts")
                    Spacer()
                    Button {
                        appState.prompts.append(PromptConfig.makeDefault())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add prompt")
                }
            } footer: {
                Text("Create named prompts to enhance transcriptions via OpenRouter.")
            }
        }
        .formStyle(.grouped)
    }
}
