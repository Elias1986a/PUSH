import Foundation
import CoreAudio
import IOKit
import PUSHCore

/// The microphones PUSH can record from.
///
/// Exists because `AVAudioEngine` binds to whatever macOS currently calls the
/// default input, and that moves underneath you: connecting AirPods, docking,
/// or joining a call can hand your dictation to a different microphone than
/// the one you set up. The fix is to let the user name a device and keep it.
///
/// Devices are identified by **UID, not `AudioDeviceID`**. The numeric id is
/// assigned at enumeration time and is not stable across reboots or even
/// across unplugging and replugging the same interface — persisting one would
/// eventually point at a different device, which is worse than not persisting
/// anything. The UID is a string the driver owns and keeps.
enum AudioInputDevices {

    struct Device: Identifiable, Hashable {
        /// CoreAudio's handle, valid only for this enumeration.
        let id: AudioDeviceID
        /// Stable across reboots — this is what gets persisted.
        let uid: String
        let name: String
        /// The Mac's own microphone, which Apple silicon MacBooks disconnect in
        /// hardware while the lid is closed.
        let isBuiltIn: Bool
        /// Software routing (BlackHole, Teams, aggregates): never a microphone
        /// to fall back to on our own.
        let isVirtual: Bool
    }

    /// Every device with at least one input channel, in CoreAudio's order.
    static func available() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
            size > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }

        return ids.compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = string(id, kAudioObjectPropertyName) ?? uid
            let transport = transportType(id)
            return Device(id: id, uid: uid, name: name,
                          isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn,
                          isVirtual: [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                                      kAudioDeviceTransportTypeAutoAggregate].contains(transport))
        }
    }

    /// The microphone to record from, or nil to leave the system default alone.
    ///
    /// The first device in `priority` that is attached wins, so a USB mic at the
    /// desk and AirPods on the go both just work. With the lid closed the
    /// built-in microphone is skipped — it records silence then — and if the
    /// system default *is* the built-in one, the first real microphone attached
    /// stands in for it.
    static func preferred(from priority: [String]) -> Device? {
        let lidClosed = isLidClosed()
        let usable = available().filter { !(lidClosed && $0.isBuiltIn) }
        for uid in priority {
            if let device = usable.first(where: { $0.uid == uid }) { return device }
        }
        guard lidClosed, systemDefault()?.isBuiltIn == true else { return nil }
        return usable.first { !$0.isVirtual }
    }

    /// Whether a laptop's lid is shut (running on an external display). False
    /// on desktops, which have no such property.
    static func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return state?.takeRetainedValue() as? Bool ?? false
    }

    /// The CoreAudio id for a saved UID, or nil if that device is not attached
    /// right now — which is the normal case for a USB interface that is simply
    /// unplugged, not an error worth surfacing until the user tries to record.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        available().first { $0.uid == uid }?.id
    }

    /// What macOS would pick on its own. Shown in the picker so "System
    /// default" can name the device it currently resolves to, rather than
    /// leaving the user to guess.
    static func systemDefault() -> Device? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
            id != 0 else { return nil }
        return available().first { $0.id == id }
    }

    // MARK: - Private

    /// A device is an input if its input scope reports at least one channel.
    /// Buffer count alone is not enough — aggregate devices advertise buffers
    /// with zero channels.
    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return false }

        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // `Unmanaged`, not a bare `CFString` variable: these are Copy-semantics
        // properties, so CoreAudio hands back a +1 reference. Pointing at a
        // `CFString` var instead makes the compiler warn that the pointee may
        // hold an object reference, and leaks the string on every read.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String? else { return nil }
        return string.isEmpty ? nil : string
    }
}
