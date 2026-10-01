import Foundation
import PUSHCore
@preconcurrency import AVFoundation

/// Audible volume for the chirp. 0.75 rather than 0.5: ducking drops system
/// output to 25% at the same moment, so a quieter chirp is nearly inaudible.
/// Deliberately NOT solved by delaying the duck — that left music loud too long.
private let chirpVolume: Float = 0.75

/// The start-of-recording sound. All are PUSH's own, synthesised for it
/// (2026-09-30) — they replaced a Nextel chirp of unknown origin, which was
/// T-Mobile's brand and not ours to ship.
enum ChirpSound: String, CaseIterable, Identifiable {
    case deepTap, micTap, brightTap, keyUp, powerOn8bit, ready8bit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .micTap: return "Mic Tap"
        case .deepTap: return "Deep Tap"
        case .brightTap: return "Bright Tap"
        case .keyUp: return "Key Up"
        case .powerOn8bit: return "8-bit Power On"
        case .ready8bit: return "8-bit Ready"
        }
    }

    var fileName: String {
        switch self {
        case .micTap: return "mic_tap"
        case .deepTap: return "deep_tap"
        case .brightTap: return "bright_tap"
        case .keyUp: return "key_up"
        case .powerOn8bit: return "power_on_8bit"
        case .ready8bit: return "ready_8bit"
        }
    }
}

/// Plays sound effects
@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private var chirpPlayer: AVAudioPlayer?
    /// Which sound `chirpPlayer` holds, so a changed setting is noticed.
    private var preparedSound: ChirpSound?
    private var isPreparing = false

    private init() {}

    /// Locate a sound — SPM resource bundle in Contents/Resources/ first,
    /// then the main bundle.
    private static func url(for sound: ChirpSound) -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "PUSH_PUSH", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleURL),
           let soundURL = resourceBundle.url(forResource: sound.fileName, withExtension: "wav") {
            return soundURL
        }
        return Bundle.main.url(forResource: sound.fileName, withExtension: "wav")
    }

    /// The setting changed: prepare the new sound and let the user hear it.
    func selectionChanged() {
        chirpPlayer = nil
        preparedSound = nil
        Task {
            await prewarm()
            preview()
        }
    }

    /// Play the chosen sound now, from Settings.
    func preview() {
        guard let player = chirpPlayer, preparedSound == AppState.shared.chirpSound else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            player.currentTime = 0
            player.play()
        }
    }

    /// Build the chirp player at launch instead of on the user's first press,
    /// and start CoreAudio's output device while nobody is waiting on it.
    ///
    /// Measured: the first `play()` of a process costs ~0.9s and `prepareToPlay()`
    /// does not avoid it — preparing allocates buffers but leaves the output unit
    /// stopped, and starting the device is the expensive half. That second landed
    /// on the main actor between the user's key press and `startRecording`, so the
    /// opening words of the first dictation were lost. Playing once at zero volume
    /// gets the device running silently.
    ///
    /// All of it runs off the main thread. Done inline it froze the main thread for
    /// ~2s at launch, which is exactly when the pill is animating in and out — the
    /// pill visibly hung mid-animation.
    func prewarm() async {
        guard chirpPlayer == nil, !isPreparing else { return }
        let sound = AppState.shared.chirpSound
        guard let url = Self.url(for: sound) else {
            PushLogger.log("SoundPlayer: Could not find \(sound.fileName).wav")
            return
        }
        isPreparing = true
        defer { isPreparing = false }

        // Building the player and starting the output device, off the main
        // thread. Done inline it froze the main thread for ~2s at launch —
        // which is when the pill is animating and when the hotkey's event tap
        // is most easily disabled.
        let built = await Task.detached(priority: .userInitiated) { () -> AVAudioPlayer? in
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            player.volume = 0
            player.prepareToPlay()
            player.play()
            return player
        }.value

        guard let player = built else {
            PushLogger.log("SoundPlayer: Failed to prepare sound")
            return
        }

        // Let the silent play actually reach the hardware before winding back.
        try? await Task.sleep(for: .milliseconds(500))
        // pause(), never stop(): `stop()` is documented to undo the setup that
        // `prepareToPlay()` performed, which threw away the very thing this is
        // warming. With stop() here the first real chirp still cost ~1.3s,
        // exactly as if nothing had been prewarmed.
        player.pause()
        player.currentTime = 0
        player.volume = chirpVolume

        // Published only once it is genuinely ready to chirp, so `playChirp` can
        // treat "no player" as "not warm yet" and skip rather than block.
        chirpPlayer = player
        preparedSound = sound
        PushLogger.log("SoundPlayer: chirp pre-warmed")
    }

    /// Play the Nextel chirp sound.
    ///
    /// Never blocks: this runs on the main actor between the user's key press and
    /// `startRecording`, so a slow path here costs them the opening words of the
    /// dictation. The chirp is a courtesy; capturing audio is the point.
    func playChirp() {
        guard let player = chirpPlayer, preparedSound == AppState.shared.chirpSound else {
            // Pressed before launch prewarming finished. Building the player now
            // would cost ~1s right in front of the recording, so skip the cue for
            // this press and warm up behind it instead.
            PushLogger.log("SoundPlayer: chirp not ready yet, skipping")
            Task { await prewarm() }
            return
        }
        // Off the main actor as well. Warming makes `play()` fast, but "fast"
        // depends on what CoreAudio has done with the output device since — and
        // this call sits directly between the key press and the recording, so it
        // must not be able to cost the user their opening words even when it is
        // slow. Nothing downstream waits on the chirp.
        DispatchQueue.global(qos: .userInitiated).async {
            // Rewind: a player that already played sits at the end and won't restart.
            player.currentTime = 0
            player.play()
        }
    }
}
