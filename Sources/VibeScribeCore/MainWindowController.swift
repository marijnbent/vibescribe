import AppKit
import Combine
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?
    private var tabSubscription: AnyCancellable?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if window == nil {
            let rootView = MainView(appState: appState)
            let hosting = NSHostingController(rootView: rootView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "VibeScribe"
            window.contentViewController = hosting
            window.center()
            window.isReleasedWhenClosed = false
            window.initialFirstResponder = nil
            window.delegate = self

            let toolbar = NSToolbar(identifier: "SettingsToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconAndLabel
            toolbar.selectedItemIdentifier = appState.selectedTab.toolbarIdentifier
            window.toolbar = toolbar
            window.toolbarStyle = .preference

            self.window = window

            tabSubscription = appState.$selectedTab.sink { [weak toolbar] tab in
                toolbar?.selectedItemIdentifier = tab.toolbarIdentifier
            }
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        tabSubscription = nil
        window = nil
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        appState.selectedTab = tab
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
