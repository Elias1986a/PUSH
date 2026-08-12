import Foundation
@preconcurrency import AVFoundation

/// Audible volume for the chirp. 0.75 rather than 0.5: ducking drops system
/// output to 25% at the same moment, so a quieter chirp is nearly inaudible.
/// Deliberately NOT solved by delaying the duck — that left music loud too long.
private let chirpVolume: Float = 0.75

/// Plays sound effects
@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private var chirpPlayer: AVAudioPlayer?
    private var isPreparing = false

    private init() {}

    /// Locate the chirp — SPM resource bundle in Contents/Resources/ first,
    /// then the main bundle.
    private static var chirpURL: URL? {
        if let bundleURL = Bundle.main.url(forResource: "PUSH_PUSH", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleURL),
           let soundURL = resourceBundle.url(forResource: "nextel_chirp", withExtension: "mp3") {
            return soundURL
        }
        return Bundle.main.url(forResource: "nextel_chirp", withExtension: "mp3")
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
    func prewarm() {
        guard chirpPlayer == nil, !isPreparing else { return }
        guard let url = Self.chirpURL else {
            PushLogger.log("SoundPlayer: Could not find nextel_chirp.mp3")
            return
        }
        isPreparing = true

        DispatchQueue.global(qos: .userInitiated).async {
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                PushLogger.log("SoundPlayer: Failed to prepare sound")
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { Self.shared.isPreparing = false }
                }
                return
            }
            player.volume = 0
            player.prepareToPlay()
            player.play()
            // Let the silent play actually reach the hardware before winding back.
            Thread.sleep(forTimeInterval: 0.5)
            player.stop()
            player.currentTime = 0
            player.volume = chirpVolume

            // Published only once it is genuinely ready to chirp, so `playChirp`
            // can treat "no player" as "not warm yet" and skip rather than block.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.shared.adopt(player) }
            }
        }
    }

    private func adopt(_ player: AVAudioPlayer) {
        chirpPlayer = player
        isPreparing = false
        PushLogger.log("SoundPlayer: chirp pre-warmed")
    }

    /// Play the Nextel chirp sound.
    ///
    /// Never blocks: this runs on the main actor between the user's key press and
    /// `startRecording`, so a slow path here costs them the opening words of the
    /// dictation. The chirp is a courtesy; capturing audio is the point.
    func playChirp() {
        guard let player = chirpPlayer else {
            // Pressed before launch prewarming finished. Building the player now
            // would cost ~1s right in front of the recording, so skip the cue for
            // this press and warm up behind it instead.
            PushLogger.log("SoundPlayer: chirp not ready yet, skipping")
            prewarm()
            return
        }
        // Rewind: a player that already played sits at the end and won't restart.
        player.currentTime = 0
        player.play()
    }
}
