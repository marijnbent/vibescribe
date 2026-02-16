import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    private let appState: AppState
    private let onToggleRecording: () -> Void
    private var window: NSWindow?

    init(appState: AppState, onToggleRecording: @escaping () -> Void) {
        self.appState = appState
        self.onToggleRecording = onToggleRecording
    }

    func show() {
        if window == nil {
            let rootView = MainView(appState: appState, onToggleRecording: onToggleRecording)
            let hosting = NSHostingController(rootView: rootView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "VibeScrib"
            window.contentViewController = hosting
            window.center()

            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
