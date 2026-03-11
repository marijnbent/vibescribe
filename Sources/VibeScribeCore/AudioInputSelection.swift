import AVFoundation
import Foundation

enum AudioInputSelection: Equatable, Hashable {
    case systemDefault
    case device(String)

    init(storedValue: String?) {
        guard let storedValue else {
            self = .systemDefault
            return
        }

        if storedValue == Self.systemDefaultStoredValue {
            self = .systemDefault
            return
        }

        if storedValue.hasPrefix(Self.deviceStoredValuePrefix) {
            let uniqueID = String(storedValue.dropFirst(Self.deviceStoredValuePrefix.count)).trimmed
            self = uniqueID.isEmpty ? .systemDefault : .device(uniqueID)
            return
        }

        self = .systemDefault
    }

    var storedValue: String {
        switch self {
        case .systemDefault:
            Self.systemDefaultStoredValue
        case .device(let uniqueID):
            "\(Self.deviceStoredValuePrefix)\(uniqueID)"
        }
    }

    private static let systemDefaultStoredValue = "system"
    private static let deviceStoredValuePrefix = "device:"
}

struct AudioInputDeviceDescriptor: Equatable, Identifiable {
    let id: String
    let name: String
}

struct ResolvedAudioInputSelection: Equatable {
    let selection: AudioInputSelection
    let selectedDevice: AudioInputDeviceDescriptor?
    let systemDefaultDevice: AudioInputDeviceDescriptor?

    var isFallbackToSystemDefault: Bool {
        if case .device = selection {
            return selectedDevice == nil && systemDefaultDevice != nil
        }
        return false
    }

    var selectedDeviceID: String? {
        switch selection {
        case .systemDefault:
            return systemDefaultDevice?.id
        case .device(let uniqueID):
            return selectedDevice?.id ?? systemDefaultDevice?.id ?? uniqueID
        }
    }

    var displayName: String {
        switch selection {
        case .systemDefault:
            guard let systemDefaultDevice else { return "System Default" }
            return "System Default (\(systemDefaultDevice.name))"
        case .device:
            if let selectedDevice {
                return selectedDevice.name
            }
            if let systemDefaultDevice {
                return "\(systemDefaultDevice.name) (fallback)"
            }
            return "Unavailable"
        }
    }
}

enum AudioInputCatalog {
    static func availableDevices() -> [AudioInputDeviceDescriptor] {
        captureDevices()
            .map(descriptor(for:))
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static func defaultDeviceDescriptor() -> AudioInputDeviceDescriptor? {
        guard let device = AVCaptureDevice.default(for: .audio) else { return nil }
        return descriptor(for: device)
    }

    static func resolvedSelection(_ selection: AudioInputSelection) -> ResolvedAudioInputSelection {
        let availableDevices = availableDevices()
        let systemDefaultDevice = defaultDeviceDescriptor()

        switch selection {
        case .systemDefault:
            return ResolvedAudioInputSelection(
                selection: selection,
                selectedDevice: nil,
                systemDefaultDevice: systemDefaultDevice
            )
        case .device(let uniqueID):
            let selectedDevice = availableDevices.first(where: { $0.id == uniqueID })
            return ResolvedAudioInputSelection(
                selection: selection,
                selectedDevice: selectedDevice,
                systemDefaultDevice: systemDefaultDevice
            )
        }
    }

    static func captureDevice(for selection: AudioInputSelection) -> AVCaptureDevice? {
        switch selection {
        case .systemDefault:
            return AVCaptureDevice.default(for: .audio)
        case .device(let uniqueID):
            return captureDevices().first(where: { $0.uniqueID == uniqueID })
                ?? AVCaptureDevice.default(for: .audio)
        }
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        discoverySession.devices
    }

    private static var discoverySession: AVCaptureDevice.DiscoverySession {
        if #available(macOS 14.0, *) {
            return AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
    }

    private static func descriptor(for device: AVCaptureDevice) -> AudioInputDeviceDescriptor {
        AudioInputDeviceDescriptor(id: device.uniqueID, name: device.localizedName)
    }
}
