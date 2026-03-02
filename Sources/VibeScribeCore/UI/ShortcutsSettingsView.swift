import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                if appState.shortcuts.isEmpty {
                    Text("No shortcuts configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($appState.shortcuts) { $shortcut in
                        HStack(spacing: 12) {
                            Picker("Key", selection: $shortcut.key) {
                                ForEach(ShortcutKey.allCases) { key in
                                    Text(key.displayName).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)

                            Picker("Mode", selection: $shortcut.mode) {
                                ForEach(ShortcutMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)

                            Button {
                                appState.shortcuts.removeAll { $0.id == shortcut.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(appState.shortcuts.count <= 1)
                            .help("Remove shortcut")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Shortcuts")
                    Spacer()
                    Button {
                        appState.shortcuts.append(ShortcutConfig.makeDefault())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add shortcut")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold — push-to-talk. Press and hold to record, release to stop.")
                    Text("Double Click — double-press to start, single press to stop.")
                    Text("Both — hold to record, or double-press to latch on and tap to stop.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
