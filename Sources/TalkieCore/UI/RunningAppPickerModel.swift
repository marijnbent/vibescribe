import AppKit
import Combine
import Foundation

struct RunningApplicationSnapshotEntry {
    var bundleIdentifier: String?
    var displayName: String?
    var bundleURL: URL?
}

struct RunningApplicationOption: Identifiable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL?

    var id: String { bundleIdentifier }
}

enum RunningAppPickerDataSource {
    static func normalizedOptions(
        from entries: [RunningApplicationSnapshotEntry],
        excludingBundleIdentifier: String?
    ) -> [RunningApplicationOption] {
        let excludedBundleIdentifier = AppPromptOverride.normalizeBundleIdentifier(excludingBundleIdentifier)
        var uniqueOptions: [String: RunningApplicationOption] = [:]

        for entry in entries {
            guard let normalizedBundleIdentifier = AppPromptOverride.normalizeBundleIdentifier(entry.bundleIdentifier) else {
                continue
            }
            guard normalizedBundleIdentifier != excludedBundleIdentifier else { continue }

            let cleanedDisplayName = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayName = cleanedDisplayName.isEmpty ? normalizedBundleIdentifier : cleanedDisplayName
            guard !displayName.isEmpty else { continue }

            if uniqueOptions[normalizedBundleIdentifier] == nil {
                uniqueOptions[normalizedBundleIdentifier] = RunningApplicationOption(
                    bundleIdentifier: normalizedBundleIdentifier,
                    displayName: displayName,
                    bundleURL: entry.bundleURL
                )
            }
        }

        return uniqueOptions.values.sorted {
            let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending
        }
    }
}

@MainActor
final class RunningAppPickerModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var apps: [RunningApplicationOption] = []
    @Published private(set) var hasLoadedSnapshot = false

    func prepareForPresentation() {
        Task { @MainActor [weak self] in
            self?.reload()
        }
    }

    func reload() {
        apps = Self.makeSnapshot()
        hasLoadedSnapshot = true
    }

    var filteredApps: [RunningApplicationOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }

        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private static func makeSnapshot() -> [RunningApplicationOption] {
        let entries = NSWorkspace.shared.runningApplications.map { app in
            RunningApplicationSnapshotEntry(
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.localizedName,
                bundleURL: app.bundleURL
            )
        }

        return RunningAppPickerDataSource.normalizedOptions(
            from: entries,
            excludingBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }
}
