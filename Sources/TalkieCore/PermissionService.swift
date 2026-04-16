import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class PermissionService: ObservableObject {
    private static let accessibilityPromptDelayNanoseconds: UInt64 = 500_000_000
    private static let microphonePromptDelayNanoseconds: UInt64 = 150_000_000

    @Published var microphonePermission: PermissionStatus = .notDetermined
    @Published var accessibilityPermission: PermissionStatus = .notDetermined

    init() {
        refreshPermissions()
    }

    func refreshPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .authorized
        case .denied, .restricted:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .denied
        }

        accessibilityPermission = AXIsProcessTrusted() ? .authorized : .denied
    }

    func requestMicrophonePermission(completion: (@Sendable () -> Void)? = nil) {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .notDetermined {
            openMicrophoneSystemSettings()
            Task { @MainActor in
                self.refreshPermissions()
                completion?()
            }
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.microphonePromptDelayNanoseconds)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPermissions()
                    completion?()
                }
            }
        }
    }

    func requestAccessibilityPermission() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Self.accessibilityPromptDelayNanoseconds)
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            if !AXIsProcessTrusted() {
                self.openAccessibilitySystemSettings()
            }
            self.refreshPermissions()
        }
    }

    func openMicrophoneSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func requestInitialPermissionsIfNeeded() {
        refreshPermissions()
        if microphonePermission == .authorized {
            requestAccessibilityPermissionIfNeeded()
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        refreshPermissions()
        if accessibilityPermission != .authorized {
            requestAccessibilityPermission()
        }
    }
}

enum PermissionStatus: String {
    case notDetermined = "Not requested"
    case denied = "Not granted"
    case authorized = "Granted"

    var isGranted: Bool {
        self == .authorized
    }

    var color: Color {
        switch self {
        case .authorized: .green
        case .denied: .orange
        case .notDetermined: .gray
        }
    }
}
