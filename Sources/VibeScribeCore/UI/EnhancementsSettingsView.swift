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
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Prompt" : trimmed
    }

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

private struct CardContainer<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                actions
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.10))
        )
    }
}

private struct PromptLibraryRow: View {
    let prompt: PromptConfig
    let usageSummary: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.displayName)
                    .font(.headline)

                Text(prompt.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text(usageSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
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

private struct AppOverrideRow: View {
    @Binding var appOverride: AppPromptOverride
    let prompts: [PromptConfig]
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            BundleIconView(
                bundleIdentifier: appOverride.appBundleIdentifier,
                bundleURL: nil,
                size: 30
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(appOverride.appDisplayName)
                    .font(.headline)
                Text(appOverride.appBundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Picker("Prompt", selection: $appOverride.promptID) {
                ForEach(prompts) { prompt in
                    Text(prompt.displayName).tag(prompt.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove override")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
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

private struct ShortcutRoutingCard: View {
    @Binding var shortcut: ShortcutConfig
    let prompts: [PromptConfig]
    let onAddOverride: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shortcut.key.displayName)
                        .font(.headline)
                    Text("Mode: \(shortcut.mode.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Prompt")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Default Prompt", selection: $shortcut.promptID) {
                    Text("None")
                        .tag(UUID?.none)
                    ForEach(prompts) { prompt in
                        Text(prompt.displayName)
                            .tag(Optional(prompt.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300, alignment: .leading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Overrides")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Only running apps appear in the picker. Overrides stay saved even when the app is not running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Add Override...", action: onAddOverride)
                        .buttonStyle(.borderedProminent)
                        .disabled(prompts.isEmpty)
                }

                if shortcut.appPromptOverrides.isEmpty {
                    Text(prompts.isEmpty
                         ? "Create a prompt before adding per-app overrides."
                         : "No app-specific overrides yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(shortcut.appPromptOverrides.indices), id: \.self) { index in
                        AppOverrideRow(
                            appOverride: Binding(
                                get: { shortcut.appPromptOverrides[index] },
                                set: { shortcut.appPromptOverrides[index] = $0 }
                            ),
                            prompts: prompts,
                            onDelete: {
                                shortcut.appPromptOverrides.remove(at: index)
                            }
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.08))
        )
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
    @ObservedObject var appState: AppState

    @StateObject private var pickerModel = RunningAppPickerModel()
    @State private var promptEditorRequest: PromptEditorRequest?
    @State private var overridePickerRequest: OverridePickerRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                openRouterCard
                promptLibraryCard
                routingCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $promptEditorRequest) { request in
            Group {
                if let promptBinding = binding(forPromptID: request.id) {
                    PromptEditorSheet(prompt: promptBinding)
                } else {
                    Text("Prompt not found.")
                        .padding(24)
                }
            }
        }
        .sheet(item: $overridePickerRequest) { request in
            RunningAppPickerSheet(model: pickerModel) { app in
                appState.upsertAppPromptOverride(
                    shortcutID: request.shortcutID,
                    appBundleIdentifier: app.bundleIdentifier,
                    appDisplayName: app.displayName
                )
            }
        }
    }

    private var openRouterCard: some View {
        CardContainer(
            title: "OpenRouter",
            subtitle: "These credentials are used whenever a prompt is applied to a transcript."
        ) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                SecureField("API Key", text: $appState.openRouterApiKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $appState.openRouterModel)
                    .textFieldStyle(.roundedBorder)
                Text("Example models: `google/gemini-2.5-flash-lite`, `openai/gpt-5-nano`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var promptLibraryCard: some View {
        CardContainer(
            title: "Prompt Library",
            subtitle: "Create reusable prompts, then route them per shortcut and per running application."
        ) {
            Button("Add Prompt") {
                let prompt = PromptConfig.makeDefault()
                appState.prompts.append(prompt)
                promptEditorRequest = PromptEditorRequest(id: prompt.id)
            }
            .buttonStyle(.borderedProminent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if appState.prompts.isEmpty {
                    Text("No prompts yet. Add a prompt first, then assign it as a default or app-specific override.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(appState.prompts) { prompt in
                        PromptLibraryRow(
                            prompt: prompt,
                            usageSummary: promptUsageSummary(for: prompt.id),
                            onEdit: {
                                promptEditorRequest = PromptEditorRequest(id: prompt.id)
                            },
                            onDelete: {
                                appState.deletePrompt(id: prompt.id)
                            }
                        )
                    }
                }
            }
        }
    }

    private var routingCard: some View {
        CardContainer(
            title: "Shortcut Routing",
            subtitle: "Set a default prompt per shortcut, then add app-specific overrides from the running-app picker."
        ) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                ForEach($appState.shortcuts) { $shortcut in
                    ShortcutRoutingCard(
                        shortcut: $shortcut,
                        prompts: appState.prompts,
                        onAddOverride: {
                            overridePickerRequest = OverridePickerRequest(shortcutID: shortcut.id)
                        }
                    )
                }
            }
        }
    }

    private func binding(forPromptID promptID: UUID) -> Binding<PromptConfig>? {
        guard let index = appState.prompts.firstIndex(where: { $0.id == promptID }) else {
            return nil
        }
        return $appState.prompts[index]
    }

    private func promptUsageSummary(for promptID: UUID) -> String {
        let defaultShortcutCount = appState.shortcuts.filter { $0.promptID == promptID }.count
        let overrideCount = appState.shortcuts.reduce(0) { partialResult, shortcut in
            partialResult + shortcut.appPromptOverrides.filter { $0.promptID == promptID }.count
        }

        switch (defaultShortcutCount, overrideCount) {
        case (0, 0):
            return "Unused"
        case (_, 0):
            return defaultShortcutCount == 1
                ? "Used as the default for 1 shortcut"
                : "Used as the default for \(defaultShortcutCount) shortcuts"
        case (0, _):
            return overrideCount == 1
                ? "Used by 1 app override"
                : "Used by \(overrideCount) app overrides"
        default:
            let defaultText = defaultShortcutCount == 1
                ? "default for 1 shortcut"
                : "default for \(defaultShortcutCount) shortcuts"
            let overrideText = overrideCount == 1
                ? "1 app override"
                : "\(overrideCount) app overrides"
            return "Used as \(defaultText) and \(overrideText)"
        }
    }
}
