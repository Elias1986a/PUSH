import Foundation
import CoreAudio

/// What PUSH does to other apps' audio while you dictate.
enum MediaBehavior: String, CaseIterable, Identifiable {
    case off
    case pause
    case duck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Do nothing"
        case .pause: return "Pause media"
        case .duck: return "Lower volume"
        }
    }
}

/// Quiets other apps' audio for the duration of a dictation, then restores it.
///
/// Two strategies, both verified to work from a Developer ID-signed app:
/// - `.pause` posts a play/pause media key. It's a *toggle*, so it is sent
///   symmetrically and only when some app holds an audio stream.
/// - `.duck` lowers the default output device's volume and restores it.
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

    private let isAnythingPlaying: () -> Bool
    private let postPlayPauseKey: () -> Void
    private let currentVolume: () -> Float32?
    private let setVolume: (Float32) -> Void
    private let defaults: UserDefaults

    /// Non-nil only while we have actively changed something, and records
    /// exactly what to undo. Restoring is always driven by this, so PUSH never
    /// "restores" state it didn't create.
    private var activeIntervention: Intervention?

    private enum Intervention {
        case paused
        case ducked(originalVolume: Float32)
    }

    convenience init() {
        self.init(
            isAnythingPlaying: { SystemAudio.isAnythingPlaying() },
            postPlayPauseKey: { SystemAudio.postPlayPauseKey() },
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

    init(isAnythingPlaying: @escaping () -> Bool,
         postPlayPauseKey: @escaping () -> Void,
         currentVolume: @escaping () -> Float32?,
         setVolume: @escaping (Float32) -> Void,
         defaults: UserDefaults) {
        self.isAnythingPlaying = isAnythingPlaying
        self.postPlayPauseKey = postPlayPauseKey
        self.currentVolume = currentVolume
        self.setVolume = setVolume
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Quiets other audio for the given behavior. Synchronous and cheap — the
    /// hotkey-to-recording path must not gain latency, so this does no waiting.
    func beginDictation(behavior: MediaBehavior) {
        guard activeIntervention == nil else { return }

        switch behavior {
        case .off:
            return

        case .pause:
            // The media key is a blind toggle: sending it with nothing loaded
            // would *start* playback. Only send it when some app actually
            // holds an audio stream.
            guard isAnythingPlaying() else {
                PushLogger.log("MediaController: nothing playing, not pausing")
                return
            }
            postPlayPauseKey()
            activeIntervention = .paused
            PushLogger.log("MediaController: sent play/pause (pause)")

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
        case .paused:
            postPlayPauseKey()
            PushLogger.log("MediaController: sent play/pause (resume)")

        case .ducked(let originalVolume):
            setVolume(originalVolume)
            defaults.removeObject(forKey: Self.interruptedDuckKey)
            PushLogger.log("MediaController: restored volume")
        }
    }

    /// Restores volume left ducked by a previous run that died mid-dictation.
    /// Call once at launch. (The pause strategy needs no equivalent: a missed
    /// resume leaves media paused, which is recoverable by the user and never
    /// leaves the machine in a confusing state the way silent audio does.)
    func restoreVolumeIfInterrupted() {
        guard let stored = defaults.object(forKey: Self.interruptedDuckKey) as? Float32 ??
                (defaults.object(forKey: Self.interruptedDuckKey) as? Double).map(Float32.init) else { return }
        defaults.removeObject(forKey: Self.interruptedDuckKey)
        guard let current = currentVolume(), current < stored else { return }
        setVolume(stored)
        PushLogger.log("MediaController: restored volume left ducked by a previous run")
    }
}
