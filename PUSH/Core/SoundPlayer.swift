import Foundation
import AVFoundation

/// Plays sound effects
class SoundPlayer {
    static let shared = SoundPlayer()

    private var audioPlayer: AVAudioPlayer?

    private init() {}

    /// Play the Nextel chirp sound
    func playChirp() {
        guard let url = Bundle.module.url(forResource: "nextel_chirp", withExtension: "mp3") else {
            print("SoundPlayer: Could not find nextel_chirp.mp3")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 0.5  // 50% volume
            audioPlayer?.play()
        } catch {
            print("SoundPlayer: Failed to play sound: \(error)")
        }
    }
}
