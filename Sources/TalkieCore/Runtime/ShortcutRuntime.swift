import AppKit
import Foundation

@MainActor
final class ShortcutRuntime {
    private let eventMonitor: EventMonitorPort
    private let clock: ClockPort
    private let stateMachine: ShortcutStateMachine

    private var hotkeyListeners: [UUID: HotkeyListener] = [:]
    private var shortcutGlobalMonitor: Any?
    private var shortcutLocalMonitor: Any?
    private var lastShortcutEventTimestamp: TimeInterval = 0
    private var lastShortcutEventKeyCode: UInt16 = 0
    private var lastShortcutEventModifiers: NSEvent.ModifierFlags = []

    private let shortcutEventDedupWindow: TimeInterval = 0.02

    var phaseProvider: (() -> RecordingPhase)?
    var ownershipProvider: (() -> RecordingOwnership?)?
    var onActions: (([ShortcutAction]) -> Void)?

    init(
        eventMonitor: EventMonitorPort,
        clock: ClockPort,
        clickHoldThreshold: TimeInterval
    ) {
        self.eventMonitor = eventMonitor
        self.clock = clock
        self.stateMachine = ShortcutStateMachine(clickHoldThreshold: clickHoldThreshold)
    }

    func configure(shortcuts: [ShortcutConfig]) {
        hotkeyListeners.removeAll()

        for shortcut in shortcuts {
            let listener = HotkeyListener(hotkey: Hotkey(shortcutKey: shortcut.key))
            let shortcutID = shortcut.id
            let mode = shortcut.mode

            listener.onKeyDown = { [weak self] in
                self?.dispatch(eventType: .keyDown, shortcutID: shortcutID, mode: mode)
            }
            listener.onKeyUp = { [weak self] in
                self?.dispatch(eventType: .keyUp, shortcutID: shortcutID, mode: mode)
            }
            hotkeyListeners[shortcut.id] = listener
        }
    }

    func start() {
        stop()

        shortcutGlobalMonitor = eventMonitor.addGlobalMonitor(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleShortcutEvent(event)
            }
        }

        shortcutLocalMonitor = eventMonitor.addLocalMonitor(matching: .flagsChanged) { [weak self] event in
            self?.handleShortcutEvent(event)
            return event
        }
    }

    func stop() {
        if let monitor = shortcutGlobalMonitor {
            eventMonitor.removeMonitor(monitor)
            shortcutGlobalMonitor = nil
        }
        if let monitor = shortcutLocalMonitor {
            eventMonitor.removeMonitor(monitor)
            shortcutLocalMonitor = nil
        }
    }

    private func handleShortcutEvent(_ event: NSEvent) {
        let normalizedModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isDuplicate = event.keyCode == lastShortcutEventKeyCode
            && normalizedModifiers == lastShortcutEventModifiers
            && abs(event.timestamp - lastShortcutEventTimestamp) <= shortcutEventDedupWindow
        if isDuplicate {
            return
        }

        lastShortcutEventTimestamp = event.timestamp
        lastShortcutEventKeyCode = event.keyCode
        lastShortcutEventModifiers = normalizedModifiers

        for listener in hotkeyListeners.values {
            listener.handle(event: event)
        }
    }

    private func dispatch(eventType: ShortcutEventType, shortcutID: UUID, mode: ShortcutMode) {
        let phase = phaseProvider?() ?? .idle
        let ownership = ownershipProvider?()

        let elapsedSinceStart: TimeInterval
        if let ownership, ownership.ownerShortcutID == shortcutID {
            elapsedSinceStart = max(0, clock.now() - ownership.recordingStartedAt)
        } else {
            elapsedSinceStart = 0
        }

        let actions = stateMachine.reduce(
            input: ShortcutStateInput(
                eventType: eventType,
                shortcutID: shortcutID,
                mode: mode,
                phase: phase,
                ownership: ownership,
                elapsedSinceStart: elapsedSinceStart
            )
        )

        guard actions != [.noop] else { return }
        onActions?(actions)
    }
}
