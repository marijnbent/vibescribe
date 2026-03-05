import AppKit
import AVFoundation
import Carbon
import Foundation

final class DispatchWorkItemTask: CancellableTask {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}

final class DispatchSchedulerAdapter: SchedulerPort {
    @discardableResult
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> CancellableTask {
        let workItem = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return DispatchWorkItemTask(workItem: workItem)
    }
}

struct SystemClockAdapter: ClockPort {
    func now() -> TimeInterval {
        CACurrentMediaTime()
    }
}

final class AudioCaptureControllerAdapter: AudioCapturePort {
    private let controller: AudioCaptureController

    init(controller: AudioCaptureController = AudioCaptureController()) {
        self.controller = controller
    }

    var onBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { controller.onBuffer }
        set { controller.onBuffer = newValue }
    }

    var onConfigurationChanged: (() -> Void)? {
        get { controller.onConfigurationChanged }
        set { controller.onConfigurationChanged = newValue }
    }

    func start() throws -> AudioStreamFormat {
        try controller.start()
    }

    func stop() {
        controller.stop()
    }
}

final class DeepgramClientAdapter: DeepgramPort, @unchecked Sendable {
    var onTranscriptEvent: ((String, Bool) -> Void)?
    var onLog: ((String, LogLevel) -> Void)?
    var onTranscriptionError: ((String) -> Void)?
    var onConnectionDropped: ((String) -> Void)?

    private lazy var client: DeepgramClient = {
        DeepgramClient(
            onTranscriptEvent: { [weak self] text, isFinal in
                self?.onTranscriptEvent?(text, isFinal)
            },
            onLog: { [weak self] message, level in
                self?.onLog?(message, level)
            },
            onTranscriptionError: { [weak self] message in
                self?.onTranscriptionError?(message)
            },
            onConnectionDropped: { [weak self] reason in
                self?.onConnectionDropped?(reason)
            }
        )
    }()

    func connect(apiKey: String, format: AudioStreamFormat, language: DeepgramLanguage) {
        client.connect(apiKey: apiKey, format: format, language: language)
    }

    func sendAudio(buffer: AVAudioPCMBuffer) {
        client.sendAudio(buffer: buffer)
    }

    func closeStream(onClosed: @escaping () -> Void) {
        client.closeStream(onClosed: onClosed)
    }

    func disconnect() {
        client.disconnect()
    }
}

struct NSSoundAdapter: SoundPort {
    func play(named: String) {
        NSSound(named: named)?.play()
    }
}

final class NSPasteboardAdapter: PasteboardPort {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func snapshot() -> PasteboardSnapshotPayload {
        let items: [[String: Data]] = pasteboard.pasteboardItems?.map { item in
            var dataByType: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type.rawValue] = data
                }
            }
            return dataByType
        } ?? []
        return PasteboardSnapshotPayload(items: items)
    }

    func writeString(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    func restore(_ snapshot: PasteboardSnapshotPayload) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let restoredItems = snapshot.items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (typeRaw, data) in dataByType {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }

    func sendPasteCommand() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return true
    }
}

struct NSEventMonitorAdapter: EventMonitorPort {
    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}
