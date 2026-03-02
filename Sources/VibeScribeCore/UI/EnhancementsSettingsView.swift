import SwiftUI

struct EnhancementsSettingsView: View {
    @ObservedObject var appState: AppState

    static let defaultPrompt = """
    Clean up the following transcription. Fix spelling, grammar, punctuation, and formatting only. \
    Do not change, remove, or rephrase any of the original words or meaning. Keep the speaker's \
    voice and intent exactly as-is.

    Remove filler words (um, uh, you know) and false starts only when they add no meaning. \
    Add paragraph breaks where topics shift naturally.

    Return only the cleaned transcription as plain text. No explanations, no quotes, no HTML tags, \
    no markdown, no preamble, no closing remarks. Just the text.
    """

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
                if appState.shortcuts.isEmpty {
                    Text("No shortcuts configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.shortcuts) { shortcut in
                        ShortcutEnhancementRow(
                            shortcut: shortcut,
                            appState: appState
                        )
                    }
                }
            } header: {
                Text("Prompts")
            } footer: {
                Text("The transcription is appended to your prompt as <transcription>…</transcription>.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutEnhancementRow: View {
    let shortcut: ShortcutConfig
    @ObservedObject var appState: AppState

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { appState.enhancementPrompts[shortcut.id] != nil },
            set: { enabled in
                if enabled {
                    appState.enhancementPrompts[shortcut.id] = EnhancementsSettingsView.defaultPrompt
                } else {
                    appState.enhancementPrompts.removeValue(forKey: shortcut.id)
                }
            }
        )
    }

    private var promptBinding: Binding<String> {
        Binding(
            get: { appState.enhancementPrompts[shortcut.id] ?? EnhancementsSettingsView.defaultPrompt },
            set: { appState.enhancementPrompts[shortcut.id] = $0 }
        )
    }

    private var isModified: Bool {
        appState.enhancementPrompts[shortcut.id] != nil
            && appState.enhancementPrompts[shortcut.id] != EnhancementsSettingsView.defaultPrompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                Toggle("Enhance", isOn: isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            } label: {
                Text("\(shortcut.key.displayName) (\(shortcut.mode.displayName))")
            }

            if isEnabled.wrappedValue {
                TextEditor(text: promptBinding)
                    .font(.caption)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                if isModified {
                    Button("Reset to Default") {
                        appState.enhancementPrompts[shortcut.id] = EnhancementsSettingsView.defaultPrompt
                    }
                    .font(.caption)
                }
            }
        }
    }
}
