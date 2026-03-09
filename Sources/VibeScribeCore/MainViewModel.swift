import Foundation

@MainActor
final class MainViewModel: ObservableObject {
    @Published var selectedTab: SettingsTab

    init(selectedTab: SettingsTab = .general) {
        self.selectedTab = selectedTab
    }
}
