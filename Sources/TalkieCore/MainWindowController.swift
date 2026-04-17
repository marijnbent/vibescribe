import AppKit
import Combine
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let mainViewModel: MainViewModel
    private let generalViewModel: GeneralSettingsViewModel
    private let shortcutsViewModel: ShortcutsSettingsViewModel
    private let enhancementsViewModel: EnhancementsSettingsViewModel
    private let historyViewModel: HistoryViewModel
    private let logsViewModel: LogsViewModel
    private var tabSubscription: AnyCancellable?

    init(
        mainViewModel: MainViewModel,
        settingsStore: SettingsStore,
        sessionState: SessionState,
        permissionService: PermissionService,
        promptRoutingService: PromptRoutingService
    ) {
        self.mainViewModel = mainViewModel
        self.generalViewModel = GeneralSettingsViewModel(
            settingsStore: settingsStore,
            permissionService: permissionService
        )
        self.shortcutsViewModel = ShortcutsSettingsViewModel(settingsStore: settingsStore)
        self.enhancementsViewModel = EnhancementsSettingsViewModel(
            settingsStore: settingsStore,
            promptRoutingService: promptRoutingService
        )
        self.historyViewModel = HistoryViewModel(
            settingsStore: settingsStore,
            sessionState: sessionState
        )
        self.logsViewModel = LogsViewModel(sessionState: sessionState)
        
        let rootView = MainView(
            mainViewModel: mainViewModel,
            generalViewModel: generalViewModel,
            shortcutsViewModel: shortcutsViewModel,
            enhancementsViewModel: enhancementsViewModel,
            historyViewModel: historyViewModel,
            logsViewModel: logsViewModel
        )
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Talkie"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.initialFirstResponder = nil
        window.delegate = nil

        super.init(window: window)

        window.delegate = self

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = mainViewModel.selectedTab.toolbarIdentifier
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        tabSubscription = mainViewModel.$selectedTab.sink { [weak toolbar] tab in
            toolbar?.selectedItemIdentifier = tab.toolbarIdentifier
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        promoteTalkieToRegularAppIfNeeded()
        let shouldCenterWindow = window?.isVisible != true
        showWindow(nil)
        if shouldCenterWindow {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func promoteTalkieToRegularAppIfNeeded() {
        guard NSApp.activationPolicy() != .regular else {
            return
        }

        NSApp.setActivationPolicy(.regular)
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        mainViewModel.selectedTab = tab
    }
}

extension MainWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.label
        item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.label)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
}
