import Foundation
import CoreAudio
import PUSHCore

/// What PUSH does to other apps' audio while you dictate.
///
/// A `.pause` case existed in 6.0.0 and was removed: macOS gives a third-party
/// app no reliable way to know whether audio is actually playing (MediaRemote
/// is gated to Apple-signed processes; a held output stream doesn't
/// distinguish playing from paused), and the play/pause media key is a blind
/// toggle. In practice it un-paused media the user had deliberately paused,
/// and with nothing playing macOS routed the key to Music.app and launched it.
/// Ducking needs no knowledge of other apps' state, so it can't fail that way.
enum MediaBehavior: String, CaseIterable, Identifiable {
    case off
    case duck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Do nothing"
        case .duck: return "Lower volume"
        }
    }
}

/// Quiets other apps' audio for the duration of a dictation, then restores it.
///
/// `.duck` lowers the default output device's volume and restores it after.
///
/// Dependencies are injected so the decision logic is testable without
/// touching real audio hardware.
@MainActor
final class MediaController {
    static let shared = MediaController()

    /// Fraction of the original volume to duck to (25% = noticeably quieter
    /// but not silent, so you can still tell something is playing).
    private static let duckFactor: Float32 = 0.25

    /// Set while ducked so a crash mid-dictation can be detected and the
    /// user's volume restored at next launch instead of being left quiet.
    private static let interruptedDuckKey = "mediaControllerDuckedVolume"

    private let currentVolume: () -> Float32?
    private let setVolume: (Float32) -> Void
    private let defaults: UserDefaults

    /// Non-nil only while we have actively changed something, and records
    /// exactly what to undo. Restoring is always driven by this, so PUSH never
    /// "restores" state it didn't create.
    private var activeIntervention: Intervention?

    private enum Intervention {
        case ducked(originalVolume: Float32)
    }

    convenience init() {
        self.init(
            currentVolume: {
                guard let device = SystemAudio.defaultOutputDevice() else { return nil }
                return SystemAudio.outputVolume(device)
            },
            setVolume: { value in
                guard let device = SystemAudio.defaultOutputDevice() else { return }
                SystemAudio.setOutputVolume(device, value)
            },
            defaults: .standard
        )
    }

    init(currentVolume: @escaping () -> Float32?,
         setVolume: @escaping (Float32) -> Void,
         defaults: UserDefaults) {
        self.currentVolume = currentVolume
        self.setVolume = setVolume
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Quiets other audio for the given behavior. Synchronous and cheap — the
    /// hotkey-to-recording path must not gain latency, so this does no waiting.
    ///
    func beginDictation(behavior: MediaBehavior) {
        guard activeIntervention == nil else { return }

        switch behavior {
        case .off:
            return

        case .duck:
            guard let original = currentVolume(), original > 0 else {
                PushLogger.log("MediaController: no settable output volume, not ducking")
                return
            }
            defaults.set(original, forKey: Self.interruptedDuckKey)
            setVolume(original * Self.duckFactor)
            activeIntervention = .ducked(originalVolume: original)
            PushLogger.log("MediaController: ducked volume")
        }
    }

    /// Undoes whatever `beginDictation` did. Safe to call unconditionally —
    /// a no-op unless we actually changed something.
    func endDictation() {
        guard let intervention = activeIntervention else { return }
        activeIntervention = nil

        switch intervention {
        case .ducked(let originalVolume):
            setVolume(originalVolume)
            defaults.removeObject(forKey: Self.interruptedDuckKey)
            PushLogger.log("MediaController: restored volume")
        }
    }

    /// Restores volume left ducked by a previous run that died mid-dictation.
    /// Call once at launch.
    func restoreVolumeIfInterrupted() {
        guard let stored = defaults.object(forKey: Self.interruptedDuckKey) as? Float32 ??
                (defaults.object(forKey: Self.interruptedDuckKey) as? Double).map(Float32.init) else { return }
        defaults.removeObject(forKey: Self.interruptedDuckKey)
        guard let current = currentVolume(), current < stored else { return }
        setVolume(stored)
        PushLogger.log("MediaController: restored volume left ducked by a previous run")
    }
}
