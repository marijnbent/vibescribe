import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general
    case shortcuts
    case enhancements
    case history
    case logs
    case about

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    var label: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .enhancements: "Enhancements"
        case .history: "History"
        case .logs: "Logs"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .enhancements: "wand.and.stars"
        case .history: "clock"
        case .logs: "list.bullet.rectangle"
        case .about: "info.circle"
        }
    }
}

struct MainView: View {
    @ObservedObject var mainViewModel: MainViewModel
    @ObservedObject var generalViewModel: GeneralSettingsViewModel
    @ObservedObject var shortcutsViewModel: ShortcutsSettingsViewModel
    @ObservedObject var enhancementsViewModel: EnhancementsSettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var logsViewModel: LogsViewModel

    var body: some View {
        Group {
            switch mainViewModel.selectedTab {
            case .general:
                GeneralSettingsView(viewModel: generalViewModel)
            case .shortcuts:
                ShortcutsSettingsView(viewModel: shortcutsViewModel)
            case .enhancements:
                EnhancementsSettingsView(viewModel: enhancementsViewModel)
            case .history:
                HistoryView(viewModel: historyViewModel)
            case .logs:
                LogsView(viewModel: logsViewModel)
            case .about:
                AboutView()
            }
        }
        .frame(minWidth: 680, minHeight: 560)
    }
}

extension MainView {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
