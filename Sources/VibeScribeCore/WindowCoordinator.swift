import AppKit

@MainActor
final class WindowCoordinator {
    private let sessionState: SessionState
    private let mainViewModel: MainViewModel
    private let mainWindowController: MainWindowController
    private let overlayWindowController: OverlayWindowController

    init(
        settingsStore: SettingsStore,
        sessionState: SessionState,
        permissionService: PermissionService,
        mainViewModel: MainViewModel,
        promptRoutingService: PromptRoutingService
    ) {
        self.sessionState = sessionState
        self.mainViewModel = mainViewModel
        self.mainWindowController = MainWindowController(
            mainViewModel: mainViewModel,
            settingsStore: settingsStore,
            sessionState: sessionState,
            permissionService: permissionService,
            promptRoutingService: promptRoutingService
        )
        self.overlayWindowController = OverlayWindowController(
            sessionState: sessionState,
            settingsStore: settingsStore
        )
    }

    func showMain(tab: SettingsTab) {
        mainViewModel.selectedTab = tab
        mainWindowController.show()
    }

    func showOverlay(label: String, appIcon: NSImage?) {
        sessionState.overlayLabel = label
        sessionState.overlayAppIcon = appIcon
        sessionState.overlayVisible = true
        overlayWindowController.show()
    }

    func hideOverlay() {
        sessionState.overlayVisible = false
        sessionState.overlayAppIcon = nil
        overlayWindowController.hide()
    }
}
