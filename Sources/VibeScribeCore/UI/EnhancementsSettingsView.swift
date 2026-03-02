import SwiftUI

private struct PromptEditSheet: View {
    @Binding var prompt: PromptConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Prompt")
                .font(.headline)

            TextField("Name", text: $prompt.name)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $prompt.content)
                .font(.body)
                .frame(minHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )

            Text("The transcription will be appended at the end of your prompt in <transcription> tags.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 440, height: 370)
    }
}

private struct PromptRow: View {
    @Binding var prompt: PromptConfig
    var shortcuts: [Binding<ShortcutConfig>]
    var onDelete: () -> Void
    @State private var isEditing = false

    var body: some View {
        HStack {
            Text(prompt.name.isEmpty ? "Untitled" : prompt.name)
                .lineLimit(1)

            Spacer()

            ForEach(shortcuts, id: \.wrappedValue.id) { $shortcut in
                Toggle(shortcut.key.displayName, isOn: Binding(
                    get: { shortcut.promptID == prompt.id },
                    set: { shortcut.promptID = $0 ? prompt.id : nil }
                ))
                .toggleStyle(.checkbox)
                .help("Use with \(shortcut.key.displayName)")
            }

            Button {
                isEditing = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit prompt")

            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove prompt")
        }
        .sheet(isPresented: $isEditing) {
            PromptEditSheet(prompt: $prompt)
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
                if appState.prompts.isEmpty {
                    Text("No prompts configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($appState.prompts) { $prompt in
                        PromptRow(
                            prompt: $prompt,
                            shortcuts: $appState.shortcuts.map { $s in $s },
                            onDelete: { appState.deletePrompt(id: prompt.id) }
                        )
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
                Text("Create named prompts to enhance transcriptions via OpenRouter. Check shortcuts to assign them.")
            }
        }
        .formStyle(.grouped)
    }
}
