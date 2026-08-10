import Foundation
import CoreAudio
import AppKit

/// Thin wrappers over the system audio facilities used to quiet other apps
/// during dictation. Split out from `MediaController` so the controller's
/// decision logic can be unit-tested with injected doubles.
///
/// Everything here is public API and works from a Developer ID-signed,
/// hardened-runtime app — verified empirically against a signed binary.
/// (MediaRemote is deliberately NOT used: macOS gates both its now-playing
/// reads and its transport commands to Apple-signed processes, so it silently
/// no-ops for third-party apps.)
enum SystemAudio {

    // MARK: - Playback detection

    /// Audio-producing processes that are not "media playback": system alert
    /// sounds (including PUSH's own start-recording chime), audio plumbing,
    /// and PUSH itself.
    private static let ignoredProcesses: Set<String> = [
        "systemsoundserverd",
        "com.apple.systemsoundserverd",
        "coreaudiod",
        "com.push.voicetotext",
    ]

    /// Bundle identifiers of processes currently running audio output,
    /// excluding system noise and PUSH itself.
    ///
    /// Caveat worth knowing: a browser keeps its output stream open while a
    /// video is *paused*, so a non-empty result means "an app holds an audio
    /// stream", not "sound is actually coming out". That's enough to skip the
    /// genuinely-idle case, which is all the pause strategy needs.
    static func processesRunningOutput() -> [String] {
        var result: [String] = []
        for object in processObjectList() {
            guard let running = uint32Property(object, kAudioProcessPropertyIsRunningOutput),
                  running != 0 else { continue }
            let name = stringProperty(object, kAudioProcessPropertyBundleID) ?? "unknown"
            guard !ignoredProcesses.contains(name) else { continue }
            result.append(name)
        }
        return result
    }

    static func isAnythingPlaying() -> Bool {
        !processesRunningOutput().isEmpty
    }

    // MARK: - Media key

    private static let playPauseKey: Int32 = 16 // NX_KEYTYPE_PLAY

    /// Posts a system-wide play/pause media key. This is a *toggle* — there is
    /// no discrete pause — so callers must send it symmetrically (once to
    /// pause, once to resume) to leave playback in its original state.
    static func postPlayPauseKey() {
        for isDown in [true, false] {
            let flags: NSEvent.ModifierFlags = isDown ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00)
            let data1 = Int((playPauseKey << 16) | ((isDown ? 0xA : 0xB) << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

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

    private static func processObjectList() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func uint32Property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
