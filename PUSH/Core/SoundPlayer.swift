import Foundation
import AVFoundation

/// Plays sound effects
@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private var audioPlayer: AVAudioPlayer?

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
            // 0.75 rather than 0.5: ducking drops system output to 25% at the
            // same moment, so a quieter chirp is nearly inaudible. Deliberately
            // NOT solved by delaying the duck — that left music loud too long.
            audioPlayer?.volume = 0.75
            audioPlayer?.play()
        } catch {
            PushLogger.log("SoundPlayer: Failed to play sound: \(error)")
        }
    }
}
