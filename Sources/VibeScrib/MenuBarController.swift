import AppKit
import Combine

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    private let openMainAction: () -> Void
    private let toggleRecordingAction: () -> Void
    private let quitAction: () -> Void

    private let recordMenuItem: NSMenuItem

    init(
        appState: AppState,
        onOpenMain: @escaping () -> Void,
        onToggleRecording: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.appState = appState
        self.openMainAction = onOpenMain
        self.toggleRecordingAction = onToggleRecording
        self.quitAction = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        recordMenuItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "r")

        statusItem.button?.title = "VibeScrib"

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open VibeScrib", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        recordMenuItem.target = self
        menu.addItem(recordMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        appState.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.recordMenuItem.title = isRecording ? "Stop Recording" : "Start Recording"
            }
            .store(in: &cancellables)
    }

    @objc private func openMainWindow() {
        openMainAction()
    }

    @objc private func toggleRecording() {
        toggleRecordingAction()
    }

    @objc private func quitApp() {
        quitAction()
    }
}
