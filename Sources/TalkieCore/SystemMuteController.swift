import CoreAudio
import Foundation

@MainActor
final class SystemMuteController {
    private var savedMuteState: Bool?
    private let onLog: (String, LogLevel) -> Void

    init(onLog: @escaping (String, LogLevel) -> Void) {
        self.onLog = onLog
    }

    func muteForRecording() {
        savedMuteState = isSystemMuted()
        setSystemMute(true)
    }

    func restoreMute() {
        guard let wasMuted = savedMuteState else { return }
        savedMuteState = nil
        setSystemMute(wasMuted)
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else { return nil }
        return deviceID
    }

    private func setSystemMute(_ mute: Bool) {
        guard let device = defaultOutputDevice() else {
            onLog("Unable to set mute state: no default output device.", .warning)
            return
        }
        var value: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        if status != noErr {
            onLog("Failed to set system mute=\(mute) (CoreAudio status \(status)).", .warning)
        }
    }

    private func isSystemMuted() -> Bool {
        guard let device = defaultOutputDevice() else {
            onLog("Unable to read mute state: no default output device.", .warning)
            return false
        }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        if status != noErr {
            onLog("Failed to read system mute state (CoreAudio status \(status)).", .warning)
            return false
        }
        return value != 0
    }
}
