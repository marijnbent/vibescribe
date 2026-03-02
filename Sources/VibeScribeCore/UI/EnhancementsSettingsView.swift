import SwiftUI

struct EnhancementsSettingsView: View {
    @ObservedObject var appState: AppState

    private static let defaultPrompt = "fix the transcription if needed. remove fillers. keep original as possible."

    var body: some View {
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

            Spacer()
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
                TextField("Prompt", text: promptBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
        }
    }
}
