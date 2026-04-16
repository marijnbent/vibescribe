import AppKit

@MainActor
public final class TalkieApp: NSObject, NSApplicationDelegate {
    public static func main() {
        let app = NSApplication.shared
        let delegate = TalkieApp()
        app.delegate = delegate
        app.run()
    }

    private var settingsStore: SettingsStore!
    private var sessionState: SessionState!
    private var permissionService: PermissionService!
    private var mainViewModel: MainViewModel!
    private var promptRoutingService: PromptRoutingService!
    private var transcriptHistoryStore: TranscriptHistoryStore!
    private var rawRecordingStore: RawRecordingStore!

    private var menuBarController: MenuBarController!
    private var windowCoordinator: WindowCoordinator!
    private var runtimeCoordinator: RuntimeCoordinator!
    private var escCancelMonitor: EscCancelMonitor!

    private let eventMonitorPort: EventMonitorPort = NSEventMonitorAdapter()
    private let schedulerPort: SchedulerPort = DispatchSchedulerAdapter()
    private let clockPort: ClockPort = SystemClockAdapter()
    private let soundPort: SoundPort = NSSoundAdapter()
    private let pasteboardPort: PasteboardPort = NSPasteboardAdapter()
    private let pasteVerificationPort: PasteVerificationPort = AccessibilityPasteVerificationAdapter()
    private var audioCapturePort: AudioCapturePort!
    private let deepgramPort: DeepgramPort = DeepgramClientAdapter()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppMenuBuilder.build()

        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

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
        sessionState.addLog("Talkie launched.", level: .info)
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

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        permissionService.refreshPermissions()
    }

    private func configureState() {
        settingsStore = SettingsStore()
        transcriptHistoryStore = TranscriptHistoryStore()
        rawRecordingStore = RawRecordingStore()
        let savedHistory = transcriptHistoryStore.loadEntries()
        sessionState = SessionState(
            historyStore: transcriptHistoryStore,
            initialTranscriptHistory: savedHistory
        )
        permissionService = PermissionService()
        mainViewModel = MainViewModel()
        promptRoutingService = PromptRoutingService()
        audioCapturePort = AudioCaptureControllerAdapter(
            controller: AudioCaptureController(
                preferredInputProvider: { [weak self] in
                    self?.settingsStore.audioInputSelection ?? .systemDefault
                }
            )
        )
        sessionState.onHistoryEntriesRemoved = { [weak rawRecordingStore] entries in
            entries.forEach { entry in
                rawRecordingStore?.deleteRecording(at: entry.rawRecordingFileURL)
            }
        }
        sessionState.applyHistoryLimit(settingsStore.historyLimit)
        rawRecordingStore.pruneRecordings(keeping: sessionState.transcriptHistory.compactMap(\.rawRecordingFileURL))
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
            permissionService: permissionService,
            promptRoutingService: promptRoutingService,
            windowCoordinator: windowCoordinator,
            rawRecordingStore: rawRecordingStore,
            schedulerPort: schedulerPort,
            clockPort: clockPort,
            soundPort: soundPort,
            pasteboardPort: pasteboardPort,
            pasteVerificationPort: pasteVerificationPort,
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
            settingsStore: settingsStore,
            onOpenMain: { [weak self] in
                self?.showSettingsWindow()
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
                self?.runtimeCoordinator.canCancelFromEsc ?? false
            },
            cancelRecording: { [weak self] in
                self?.runtimeCoordinator.cancelFromEsc()
            }
        )
    }

    private func showSettingsWindow() {
        windowCoordinator.showSettings()
    }
}
