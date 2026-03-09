import AppKit
import Carbon

@MainActor
final class EscCancelMonitor {
    private let eventMonitor: EventMonitorPort
    private let isEnabled: () -> Bool
    private let shouldCancel: () -> Bool
    private let cancelRecording: () -> Void

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(
        eventMonitor: EventMonitorPort,
        isEnabled: @escaping () -> Bool,
        shouldCancel: @escaping () -> Bool,
        cancelRecording: @escaping () -> Void
    ) {
        self.eventMonitor = eventMonitor
        self.isEnabled = isEnabled
        self.shouldCancel = shouldCancel
        self.cancelRecording = cancelRecording
    }

    func start() {
        stop()

        let escKeyCode = UInt16(kVK_Escape)
        globalMonitor = eventMonitor.addGlobalMonitor(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escKeyCode else { return }
            Task { @MainActor in
                guard let self else { return }
                self.handleEsc()
            }
        }

        localMonitor = eventMonitor.addLocalMonitor(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escKeyCode else { return event }
            Task { @MainActor in
                guard let self else { return }
                self.handleEsc()
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            eventMonitor.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            eventMonitor.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleEsc() {
        guard isEnabled(), shouldCancel() else { return }
        cancelRecording()
    }
}
