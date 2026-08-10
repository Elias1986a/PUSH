import Foundation
import CoreAudio

/// Thin wrappers over the system audio facilities used to quiet other apps
/// during dictation. Split out from `MediaController` so the controller's
/// decision logic can be unit-tested with injected doubles.
///
/// Public API only, verified from a Developer ID-signed, hardened-runtime app.
///
/// Deliberately does NOT try to pause other apps. MediaRemote's now-playing
/// reads and transport commands are both gated to Apple-signed processes, and
/// the play/pause media key is a blind toggle that starts media when nothing
/// is playing — including launching Music.app. Ducking needs no knowledge of
/// other apps, so it has none of those failure modes.
enum SystemAudio {

    // MARK: - Output volume

    static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr else { return nil }
        return device
    }

    /// Master output volume (0...1), or nil if this device has no master
    /// control — some virtual devices only expose per-channel volume.
    static func outputVolume(_ device: AudioDeviceID) -> Float32? {
        var address = volumeAddress(element: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else {
            return channelVolumes(device).first?.value
        }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    static func setOutputVolume(_ device: AudioDeviceID, _ value: Float32) -> Bool {
        let clamped = max(0, min(1, value))
        var address = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &address) {
            var volume = clamped
            return AudioObjectSetPropertyData(device, &address, 0, nil,
                                              UInt32(MemoryLayout<Float32>.size), &volume) == noErr
        }
        // Per-channel fallback for devices without a master control.
        let channels = channelVolumes(device)
        guard !channels.isEmpty else { return false }
        var allSucceeded = true
        for channel in channels {
            var channelAddress = volumeAddress(element: channel.element)
            var volume = clamped
            let status = AudioObjectSetPropertyData(device, &channelAddress, 0, nil,
                                                    UInt32(MemoryLayout<Float32>.size), &volume)
            if status != noErr { allSucceeded = false }
        }
        return allSucceeded
    }

    // MARK: - Private

    private static func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    private static func channelVolumes(_ device: AudioDeviceID) -> [(element: AudioObjectPropertyElement, value: Float32)] {
        var result: [(AudioObjectPropertyElement, Float32)] = []
        for channel in UInt32(1)...UInt32(2) {
            var address = volumeAddress(element: channel)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                result.append((channel, value))
            }
        }
        return result
    }



}
