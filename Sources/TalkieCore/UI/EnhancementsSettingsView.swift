import AppKit
import SwiftUI

private struct PromptEditorRequest: Identifiable {
    let id: UUID
}

private struct OverridePickerRequest: Identifiable {
    let shortcutID: UUID

    var id: UUID { shortcutID }
}

private extension PromptConfig {
    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No prompt content yet." }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct PromptEditorSheet: View {
    @Binding var prompt: PromptConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.displayName)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Prompt name", text: $prompt.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt.content)
                    .font(.body)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.18))
                    )
            }

            Text("The transcript is appended automatically inside <transcription> tags before the OpenRouter request is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 470)
    }
}

private struct BundleIconView: View {
    let bundleIdentifier: String?
    let bundleURL: URL?
    let size: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .fill(Color.secondary.opacity(0.10))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .task(id: cacheKey) {
            icon = loadIcon()
        }
    }

    private var cacheKey: String {
        if let bundleURL {
            return bundleURL.path
        }
        return bundleIdentifier ?? "unknown"
    }

    private func loadIcon() -> NSImage? {
        if let bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        guard let bundleIdentifier,
              let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: bundleURL.path)
    }
}

private struct PickerEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct RunningAppPickerSheet: View {
    @ObservedObject var model: RunningAppPickerModel
    let onPick: (RunningApplicationOption) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick Running Application")
                        .font(.title3.weight(.semibold))
                    Text("Only applications that are running right now can be selected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reload") {
                    model.reload()
                }
                .buttonStyle(.bordered)
            }

            TextField("Search running apps", text: $model.searchText)
                .textFieldStyle(.roundedBorder)

            Group {
                if !model.hasLoadedSnapshot {
                    PickerEmptyState(
                        title: "Loading Running Apps",
                        systemImage: "bolt.horizontal.circle",
                        message: "The picker opens immediately and refreshes from the current running-app snapshot."
                    )
                } else if model.apps.isEmpty {
                    PickerEmptyState(
                        title: "No Running Apps Found",
                        systemImage: "app.slash",
                        message: "Launch the app you want to target, then click Reload."
                    )
                } else if model.filteredApps.isEmpty {
                    PickerEmptyState(
                        title: "No Matches",
                        systemImage: "magnifyingglass",
                        message: "Try a different search term or reload the running-app list."
                    )
                } else {
                    List(model.filteredApps) { app in
                        Button {
                            onPick(app)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                BundleIconView(
                                    bundleIdentifier: app.bundleIdentifier,
                                    bundleURL: app.bundleURL,
                                    size: 28
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.displayName)
                                        .foregroundStyle(.primary)
                                    Text(app.bundleIdentifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minHeight: 320)

            HStack {
                Text("Search is local to the current running-app snapshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .onAppear {
            model.prepareForPresentation()
        }
    }
}

struct EnhancementsSettingsView: View {
    @ObservedObject var viewModel: EnhancementsSettingsViewModel

    @StateObject private var pickerModel = RunningAppPickerModel()
    @State private var promptEditorRequest: PromptEditorRequest?
    @State private var overridePickerRequest: OverridePickerRequest?

    var body: some View {
        Form {
            openRouterSection
            promptLibrarySection
            routingSections
        }
        .formStyle(.grouped)
        .sheet(item: $promptEditorRequest) { request in
            Group {
                if let promptBinding = viewModel.bindingForPromptID(request.id) {
                    PromptEditorSheet(prompt: promptBinding)
                } else {
                    Text("Prompt not found.")
                        .padding(24)
                }
            }
        }
        .sheet(item: $overridePickerRequest) { request in
            RunningAppPickerSheet(model: pickerModel) { app in
                viewModel.upsertAppPromptOverride(
                    shortcutID: request.shortcutID,
                    appBundleIdentifier: app.bundleIdentifier,
                    appDisplayName: app.displayName
                )
            }
        }
    }

    @ViewBuilder
    private var openRouterSection: some View {
        Section {
            SecureField("API Key", text: viewModel.binding(for: \.openRouterApiKey))
            TextField("Model", text: viewModel.binding(for: \.openRouterModel))
        } header: {
            Text("OpenRouter")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("These credentials are used whenever a prompt is applied to a transcript.")
                Text("Suggested model: `inception/mercury-2`.")
                Text("Use this one if you want the fastest enhancement response.")
            }
        }
    }

    @ViewBuilder
    private var promptLibrarySection: some View {
        Section {
            if viewModel.prompts.isEmpty {
                Text("No prompts yet. Add a prompt first, then assign it as a default or app-specific override.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.prompts) { prompt in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prompt.displayName)
                                .font(.headline)
                            Text(prompt.previewText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(viewModel.promptUsageSummary(for: prompt.id))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 12)

                        HStack(spacing: 8) {
                            Button("Edit") {
                                promptEditorRequest = PromptEditorRequest(id: prompt.id)
                            }
                            Button("Delete", role: .destructive) {
                                viewModel.deletePrompt(id: prompt.id)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            HStack {
                Text("Prompt Library")
                Spacer()
                Button("Add Prompt") {
                    let prompt = viewModel.addPrompt()
                    promptEditorRequest = PromptEditorRequest(id: prompt.id)
                }
                .font(.caption.weight(.medium))
            }
        } footer: {
            Text("Create reusable prompts, then route them per shortcut and per running application.")
        }
    }

    @ViewBuilder
    private var routingSections: some View {
        ForEach(viewModel.shortcuts) { shortcut in
            if let shortcutBinding = viewModel.bindingForShortcutID(shortcut.id) {
                Section {
                    Picker("Default Prompt", selection: shortcutBinding.promptID) {
                        Text("None").tag(UUID?.none)
                        ForEach(viewModel.prompts) { prompt in
                            Text(prompt.displayName).tag(Optional(prompt.id))
                        }
                    }

                    ForEach(Array(shortcutBinding.wrappedValue.appPromptOverrides.indices), id: \.self) { index in
                        HStack(alignment: .center, spacing: 12) {
                            BundleIconView(
                                bundleIdentifier: shortcutBinding.wrappedValue.appPromptOverrides[index].appBundleIdentifier,
                                bundleURL: nil,
                                size: 28
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(shortcutBinding.wrappedValue.appPromptOverrides[index].appDisplayName)
                                    .font(.headline)
                                Text(shortcutBinding.wrappedValue.appPromptOverrides[index].appBundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Picker(
                                "Prompt",
                                selection: Binding(
                                    get: { shortcutBinding.wrappedValue.appPromptOverrides[index].promptID },
                                    set: { newValue in
                                        var updated = shortcutBinding.wrappedValue
                                        updated.appPromptOverrides[index].promptID = newValue
                                        shortcutBinding.wrappedValue = updated
                                    }
                                )
                            ) {
                                ForEach(viewModel.prompts) { prompt in
                                    Text(prompt.displayName).tag(prompt.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            .labelsHidden()

                            Button(role: .destructive) {
                                var updated = shortcutBinding.wrappedValue
                                updated.appPromptOverrides.remove(at: index)
                                shortcutBinding.wrappedValue = updated
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove override")
                        }
                        .padding(.vertical, 2)
                    }

                    Button("Add App Override...") {
                        overridePickerRequest = OverridePickerRequest(shortcutID: shortcut.id)
                    }
                    .disabled(viewModel.prompts.isEmpty)
                } header: {
                    Text("\(shortcut.key.displayName) · \(shortcut.mode.displayName)")
                } footer: {
                    if shortcut.appPromptOverrides.isEmpty {
                        Text(viewModel.prompts.isEmpty
                             ? "Create a prompt before adding per-app overrides."
                             : "Only running apps appear in the picker. Overrides stay saved even when the app is not running.")
                    }
                }
            }
        }
    }
}
