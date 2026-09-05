import Foundation

/// Turns raw PCM into the 0…1 number the pill's waveform draws.
///
/// Lives in PUSHCore rather than next to `AudioRecorder` because it is pure
/// arithmetic over a sample buffer — no AVFoundation, no actor — so it can be
/// exercised without a microphone.
///
/// Two things make this display-worthy rather than a raw RMS readout:
///
/// - **It works in decibels.** Speech RMS is a small number that hugs zero
///   (roughly 0.005–0.3 for normal talking into a laptop mic), so drawing bars
///   straight from the linear value leaves them nearly flat until someone
///   shouts. Hearing is logarithmic; the bars should be too.
/// - **It is asymmetrically smoothed.** Attack is fast so a bar is already up
///   by the time the user hears their own consonant, release is slow so the
///   waveform settles instead of strobing between syllables.
public struct AudioLevelMeter {

    /// The smoothed level, 0…1. What the view draws.
    public private(set) var level: Float = 0

    /// dBFS mapped to 0. Below this is room tone on a quiet desk, not speech.
    private let floorDB: Float
    /// dBFS mapped to 1. Deliberately well under 0 dBFS: nobody dictates at
    /// full scale, and a ceiling at 0 would keep the bars in the bottom third
    /// of their travel for every real voice.
    private let ceilingDB: Float
    /// Per-buffer weight toward a *louder* target.
    private let attack: Float
    /// Per-buffer weight toward a *quieter* target.
    private let release: Float

    public init(
        floorDB: Float = -52,
        ceilingDB: Float = -12,
        attack: Float = 0.6,
        release: Float = 0.18
    ) {
        self.floorDB = floorDB
        self.ceilingDB = ceilingDB
        self.attack = attack
        self.release = release
    }

    /// Root mean square of a buffer — its average power, which is what the ear
    /// tracks. Peak would spike on a single click and miss a sustained vowel.
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let mean = sum / Float(samples.count)
        // A denormal or a NaN anywhere in the buffer would otherwise propagate
        // into `level` and freeze the waveform for the rest of the dictation.
        guard mean.isFinite, mean > 0 else { return 0 }
        return mean.squareRoot()
    }

    /// Map an RMS amplitude onto 0…1 through the meter's dB window.
    public static func normalized(rms: Float, floorDB: Float, ceilingDB: Float) -> Float {
        guard rms > 0, rms.isFinite, ceilingDB > floorDB else { return 0 }
        let db = 20 * log10(rms)
        guard db.isFinite else { return 0 }
        return min(max((db - floorDB) / (ceilingDB - floorDB), 0), 1)
    }

    /// Fold one capture buffer in and return the new smoothed level.
    @discardableResult
    public mutating func push(_ samples: [Float]) -> Float {
        let target = Self.normalized(
            rms: Self.rms(samples),
            floorDB: floorDB,
            ceilingDB: ceilingDB
        )
        level += (target - level) * (target > level ? attack : release)
        return level
    }

    /// Drop back to silence between dictations, so the next one does not open
    /// with the tail of the last one's decay.
    public mutating func reset() {
        level = 0
    }
}
