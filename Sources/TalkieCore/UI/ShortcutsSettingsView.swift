import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var viewModel: ShortcutsSettingsViewModel

    var body: some View {
        Form {
            Section {
                if viewModel.shortcuts.isEmpty {
                    Text("No shortcuts configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.shortcuts) { shortcut in
                        if let shortcutBinding = viewModel.binding(forShortcutID: shortcut.id) {
                            let usedKeys = viewModel.usedKeys(excluding: shortcut.id)
                            HStack(spacing: 12) {
                                Picker("Key", selection: shortcutBinding.key) {
                                    ForEach(ShortcutKey.allCases.filter { $0 == shortcut.key || !usedKeys.contains($0) }) { key in
                                        Text(key.displayName).tag(key)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 180)

                                Picker("Mode", selection: shortcutBinding.mode) {
                                    ForEach(ShortcutMode.allCases) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 160)

                                Button {
                                    viewModel.removeShortcut(id: shortcut.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(viewModel.shortcuts.count <= 1)
                                .help("Remove shortcut")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Shortcuts")
                    Spacer()
                    Button {
                        viewModel.addShortcut()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!viewModel.canAddShortcut)
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
