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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enhancements")
                    .font(.headline)

                GroupBox("OpenRouter") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("API Key", text: $appState.openRouterApiKey)
                        TextField("Model", text: $appState.openRouterModel)
                        Text("Enter your OpenRouter API key and model identifier (e.g. openai/gpt-4o-mini).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Per-Shortcut Enhancement") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("The transcription is appended to your prompt as <transcription>…</transcription>.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if appState.shortcuts.isEmpty {
                            Text("No shortcuts configured.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(appState.shortcuts) { shortcut in
                                shortcutEnhancementRow(shortcut)
                                if shortcut.id != appState.shortcuts.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shortcutEnhancementRow(_ shortcut: ShortcutConfig) -> some View {
        let isEnabled = Binding<Bool>(
            get: { appState.enhancementPrompts[shortcut.id] != nil },
            set: { enabled in
                if enabled {
                    appState.enhancementPrompts[shortcut.id] = Self.defaultPrompt
                } else {
                    appState.enhancementPrompts.removeValue(forKey: shortcut.id)
                }
            }
        )

        let promptBinding = Binding<String>(
            get: { appState.enhancementPrompts[shortcut.id] ?? Self.defaultPrompt },
            set: { appState.enhancementPrompts[shortcut.id] = $0 }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(shortcut.key.displayName) (\(shortcut.mode.displayName))")
                    .font(.subheadline)
                Spacer()
                Toggle("Enhance", isOn: isEnabled)
                    .toggleStyle(.switch)
            }
            if isEnabled.wrappedValue {
                TextEditor(text: promptBinding)
                    .font(.caption)
                    .frame(height: 60)
                    .border(Color.secondary.opacity(0.3))
            }
        }
    }
}
