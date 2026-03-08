import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let appState: AppState
    private var panel: NSPanel?
    private var isShowing = false
    private var animationID = UUID()

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        appState.overlayPulseID = UUID()
        guard let panel else { return }
        isShowing = true
        animationID = UUID()

        guard let screen = NSScreen.main else {
            panel.orderFrontRegardless()
            return
        }

        let target = targetFrame(screen: screen)
        let offscreen = offscreenFrame(screen: screen, width: target.width, height: target.height)

        panel.alphaValue = 0
        panel.setFrame(offscreen, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    func hide() {
        guard let panel else { return }
        guard isShowing else { return }
        isShowing = false
        let hideID = animationID

        guard let screen = NSScreen.main else {
            panel.orderOut(nil)
            return
        }

        let target = targetFrame(screen: screen)
        let offscreen = offscreenFrame(screen: screen, width: target.width, height: target.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(offscreen, display: true)
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.animationID == hideID, !self.isShowing else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let overlayView = OverlayView(appState: appState)
        let hosting = NSHostingController(rootView: overlayView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 90, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        if let contentView = panel.contentView {
            hosting.view.frame = contentView.bounds
            hosting.view.autoresizingMask = [.width, .height]
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        if let screen = NSScreen.main {
            let target = targetFrame(screen: screen)
            panel.setFrame(target, display: false)
        }

        return panel
    }

    private func targetFrame(screen: NSScreen) -> CGRect {
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let width = min(overlayWidth, fullFrame.width - 80)
        let height: CGFloat = 32
        let x = fullFrame.midX - width / 2
        let y: CGFloat
        switch appState.overlayPosition {
        case .top:
            y = visibleFrame.maxY - height - 28
        case .bottom:
            y = visibleFrame.minY + 28
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private var overlayWidth: CGFloat {
        appState.overlayAppIcon == nil ? 90 : 116
    }

    private func offscreenFrame(screen: NSScreen, width: CGFloat, height: CGFloat) -> CGRect {
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let x = fullFrame.midX - width / 2
        let y: CGFloat
        switch appState.overlayPosition {
        case .top:
            y = visibleFrame.maxY + 8
        case .bottom:
            y = visibleFrame.minY - height - 8
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
