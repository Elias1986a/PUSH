import Foundation
import AVFoundation

/// Plays sound effects
@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private var audioPlayer: AVAudioPlayer?

    /// Length of the start chirp, so callers can avoid stepping on it —
    /// ducking the output volume mid-chirp makes the cue nearly inaudible.
    /// Falls back to a small non-zero value if the file can't be measured.
    private(set) lazy var chirpDuration: TimeInterval = {
        guard let url = Self.chirpURL,
              let player = try? AVAudioPlayer(contentsOf: url) else { return 0.25 }
        return player.duration
    }()

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

    /// Play the Nextel chirp sound
    func playChirp() {
        guard let url = Self.chirpURL else {
            PushLogger.log("SoundPlayer: Could not find nextel_chirp.mp3")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 0.5  // 50% volume
            audioPlayer?.play()
        } catch {
            PushLogger.log("SoundPlayer: Failed to play sound: \(error)")
        }
    }
}
