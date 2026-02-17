import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem

    private let openMainAction: () -> Void
    private let quitAction: () -> Void

    init(
        onOpenMain: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.openMainAction = onOpenMain
        self.quitAction = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        statusItem.button?.title = "VibeScrib"

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Settings", action: #selector(openMainWindow), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openMainWindow() {
        openMainAction()
    }

    @objc private func quitApp() {
        quitAction()
    }
}
