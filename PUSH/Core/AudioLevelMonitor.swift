import Foundation
import Combine
import PUSHCore

/// Publishes the microphone level for the pill's waveform.
///
/// Deliberately its own object rather than another `@Published` on `AppState`.
/// This changes with every capture buffer — about twelve times a second — and
/// every view holding `@EnvironmentObject var appState` re-evaluates its body
/// on each `AppState` change, including the whole Settings form if it happens
/// to be open. Only `FloatingPillView` cares about the level, so only it should
/// pay for it.
///
/// The same reasoning keeps this off `.appStateDidChange`: that notification
/// drives whether the pill *window* is on screen, and visibility cannot change
/// because someone got louder. Posting it at buffer rate would put a window
/// layout in the audio path — and a main-thread stall is how this app loses its
/// CGEvent tap.
@MainActor
final class AudioLevelMonitor: ObservableObject {
    static let shared = AudioLevelMonitor()

    /// Smoothed level, 0…1. Zero whenever nothing is being captured, so a view
    /// can read it without also checking `AppState.isCapturing`.
    @Published private(set) var level: Double = 0

    private var meter = AudioLevelMeter()

    private init() {}

    /// Fold in one capture buffer. Called from `AudioRecorder`'s drain loop.
    func consume(_ samples: [Float]) {
        level = Double(meter.push(samples))
    }

    /// Back to silence, so the next dictation does not open on the tail of the
    /// last one's decay.
    func reset() {
        meter.reset()
        level = 0
    }
}
