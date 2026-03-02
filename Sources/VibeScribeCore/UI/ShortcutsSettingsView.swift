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
                        let usedKeys = Set(appState.shortcuts.filter { $0.id != shortcut.id }.map(\.key))
                        HStack(spacing: 12) {
                            Picker("Key", selection: $shortcut.key) {
                                ForEach(ShortcutKey.allCases.filter { $0 == shortcut.key || !usedKeys.contains($0) }) { key in
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
                        let usedKeys = Set(appState.shortcuts.map(\.key))
                        if let nextKey = ShortcutKey.allCases.first(where: { !usedKeys.contains($0) }) {
                            appState.shortcuts.append(ShortcutConfig(id: UUID(), key: nextKey, mode: .both))
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(appState.shortcuts.count >= ShortcutKey.allCases.count)
                    .help("Add shortcut")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold — push-to-talk. Press and hold to record, release to stop.")
                    Text("Click — press to start, press again to stop.")
                    Text("Both — hold to record, or quick-press to latch on and press to stop.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
