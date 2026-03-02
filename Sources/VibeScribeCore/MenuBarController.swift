import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem

    private let openMainAction: () -> Void
    private let openHistoryAction: () -> Void
    private let quitAction: () -> Void

    init(
        onOpenMain: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.openMainAction = onOpenMain
        self.openHistoryAction = onOpenHistory
        self.quitAction = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VibeScribe")
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Settings", action: #selector(openMainWindow), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        let historyItem = NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openMainWindow() {
        openMainAction()
    }

    @objc private func openHistory() {
        openHistoryAction()
    }

    @objc private func quitApp() {
        quitAction()
    }
}
