import AppKit

@MainActor
public final class VibeScribeApp: NSObject, NSApplicationDelegate {
    public static func main() {
        let app = NSApplication.shared
        let delegate = VibeScribeApp()
        app.delegate = delegate
        app.run()
    }

    private var settingsStore: SettingsStore!
    private var sessionState: SessionState!
    private var permissionService: PermissionService!
    private var mainViewModel: MainViewModel!
    private var promptRoutingService: PromptRoutingService!

    private var menuBarController: MenuBarController!
    private var windowCoordinator: WindowCoordinator!
    private var runtimeCoordinator: RuntimeCoordinator!
    private var escCancelMonitor: EscCancelMonitor!

    private let eventMonitorPort: EventMonitorPort = NSEventMonitorAdapter()
    private let schedulerPort: SchedulerPort = DispatchSchedulerAdapter()
    private let clockPort: ClockPort = SystemClockAdapter()
    private let soundPort: SoundPort = NSSoundAdapter()
    private let pasteboardPort: PasteboardPort = NSPasteboardAdapter()
    private let audioCapturePort: AudioCapturePort = AudioCaptureControllerAdapter()
    private let deepgramPort: DeepgramPort = DeepgramClientAdapter()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppMenuBuilder.build()

        configureState()
        configureWindows()
        configureRuntime()
        configureMenuBar()
        configureEscCancelMonitor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        runtimeCoordinator.start()
        escCancelMonitor.start()
        permissionService.requestInitialPermissionsIfNeeded()
        sessionState.addLog("VibeScribe launched.", level: .info)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        runtimeCoordinator.stop()
        escCancelMonitor.stop()
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        permissionService.refreshPermissions()
    }

    private func configureState() {
        settingsStore = SettingsStore()
        sessionState = SessionState()
        permissionService = PermissionService()
        mainViewModel = MainViewModel()
        promptRoutingService = PromptRoutingService()
    }

    private func configureWindows() {
        windowCoordinator = WindowCoordinator(
            settingsStore: settingsStore,
            sessionState: sessionState,
            permissionService: permissionService,
            mainViewModel: mainViewModel,
            promptRoutingService: promptRoutingService
        )
    }

    private func configureRuntime() {
        runtimeCoordinator = RuntimeCoordinator(
            settingsStore: settingsStore,
            sessionState: sessionState,
            promptRoutingService: promptRoutingService,
            windowCoordinator: windowCoordinator,
            schedulerPort: schedulerPort,
            clockPort: clockPort,
            soundPort: soundPort,
            pasteboardPort: pasteboardPort,
            audioCapturePort: audioCapturePort,
            deepgramPort: deepgramPort,
            eventMonitorPort: eventMonitorPort,
            activeApplicationProvider: {
                let app = NSWorkspace.shared.frontmostApplication
                return ActiveApplicationContext(
                    bundleIdentifier: app?.bundleIdentifier,
                    icon: app?.icon
                )
            }
        )
    }

    private func configureMenuBar() {
        menuBarController = MenuBarController(
            onOpenMain: { [weak self] in
                self?.windowCoordinator.showMain(tab: .general)
            },
            onOpenHistory: { [weak self] in
                self?.windowCoordinator.showMain(tab: .history)
            },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    private func configureEscCancelMonitor() {
        escCancelMonitor = EscCancelMonitor(
            eventMonitor: eventMonitorPort,
            isEnabled: { [weak self] in
                self?.settingsStore.escToCancelRecording ?? false
            },
            shouldCancel: { [weak self] in
                self?.runtimeCoordinator.isRecording ?? false
            },
            cancelRecording: { [weak self] in
                self?.runtimeCoordinator.cancelFromEsc()
            }
        )
    }
}
