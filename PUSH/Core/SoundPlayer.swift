import Foundation
import AVFoundation

/// Plays sound effects
@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private var audioPlayer: AVAudioPlayer?

    private init() {}

    /// Play the Nextel chirp sound
    func playChirp() {
        // Find the sound file — check the PUSH resource bundle first, then main bundle
        let url: URL? = {
            // SPM resource bundle in Contents/Resources/
            if let bundleURL = Bundle.main.url(forResource: "PUSH_PUSH", withExtension: "bundle"),
               let resourceBundle = Bundle(url: bundleURL),
               let soundURL = resourceBundle.url(forResource: "nextel_chirp", withExtension: "mp3") {
                return soundURL
            }
            // Fallback: directly in main bundle
            return Bundle.main.url(forResource: "nextel_chirp", withExtension: "mp3")
        }()

        guard let url else {
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
