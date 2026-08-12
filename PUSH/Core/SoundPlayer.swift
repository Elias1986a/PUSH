import Foundation
import AVFoundation

/// Plays sound effects
@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private var chirpPlayer: AVAudioPlayer?

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

    /// Build the chirp player at launch instead of on the user's first press.
    ///
    /// `playChirp()` used to construct an `AVAudioPlayer` every time it ran, so
    /// the first press of a session paid for opening the nested resource bundle,
    /// decoding the mp3, and CoreAudio spinning up an output unit — all on the
    /// main actor, between the key press and `startRecording`. Reuse also means
    /// later presses stop re-decoding the same file.
    func prewarm() {
        guard chirpPlayer == nil else { return }
        guard let url = Self.chirpURL else {
            PushLogger.log("SoundPlayer: Could not find nextel_chirp.mp3")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            // 0.75 rather than 0.5: ducking drops system output to 25% at the
            // same moment, so a quieter chirp is nearly inaudible. Deliberately
            // NOT solved by delaying the duck — that left music loud too long.
            player.volume = 0.75
            player.prepareToPlay()
            chirpPlayer = player
            PushLogger.log("SoundPlayer: chirp pre-warmed")
        } catch {
            PushLogger.log("SoundPlayer: Failed to prepare sound: \(error)")
        }
    }

    /// Play the Nextel chirp sound
    func playChirp() {
        // Falls back to building it now if launch prewarming didn't run or failed.
        if chirpPlayer == nil { prewarm() }
        guard let player = chirpPlayer else { return }
        // Rewind: a player that already played sits at the end and won't restart.
        player.currentTime = 0
        player.play()
    }
}
