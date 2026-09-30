import Foundation
import FluidAudio

/// Long-audio transcription for the Parakeet batch engines, cut at sentence ends.
///
/// The encoders take at most 15 s. Past that, FluidAudio splits the audio into
/// fixed overlapping windows and decodes each from a fresh state. A window that
/// starts mid-sentence sometimes puts the model into a mode where it emits no
/// punctuation and no capitals for the whole window — measured on real 25 s
/// dictations: 4 of 10 lost everything after the first seam ("… 15.2 seconds i
/// mean 1.52 seconds everyone who tried it said quote …"), and the same audio
/// window decoded on its own, with no merging at all, did the same. It depends
/// only on where the window starts, which is why it came and went between runs.
///
/// So windows here start where the model's own training utterances start: at a
/// sentence. Decode 15 s, keep the text through its last trustworthy sentence
/// end, start the next window in the pause after it, repeat. Each window after
/// the first is then, to the model, a fresh utterance that begins at a capital.
///
/// Short audio (one window) never comes here.
enum SentenceAlignedWindows {

    /// The encoders' fixed input: 15 s at 16 kHz.
    static let windowSamples = 240_000
    static let sampleRate = 16_000.0

    /// A window's last second and a half is not trusted for a cut: the model
    /// ends a truncated window with a full stop of its own ("15.2.") and
    /// squeezes the timings of its last words, and a cut there repeated a word
    /// across the seam ("seconds.seconds").
    static let endGuardSeconds = 1.5

    /// A cut must move forward by at least this much, so a window whose only
    /// sentence end is right at its start cannot loop.
    static let minimumProgressSeconds = 2.0

    struct Decoded {
        let text: String
        let tokens: [TokenTiming]
    }

    /// Where to end a window: the last sentence end — ".", "?" or "!" followed
    /// by a capitalised word — that is clear of the window's end. Returns the
    /// index of the terminator and the cut time, midway through the pause.
    static func cut(in tokens: [TokenTiming], windowSeconds: Double) -> (through: Int, at: Double)? {
        guard tokens.count > 1 else { return nil }
        var best: (through: Int, at: Double)?
        for k in 0..<(tokens.count - 1) where [".", "?", "!"].contains(piece(tokens[k]).trimmingCharacters(in: .whitespaces)) {
            let next = tokens[k + 1]
            let word = piece(next)
            guard word.first == " ", word.dropFirst().first?.isUppercase == true,
                  next.startTime >= minimumProgressSeconds,
                  next.startTime <= windowSeconds - endGuardSeconds else { continue }
            best = (k, (tokens[k].endTime + next.startTime) / 2)
        }
        return best
    }

    /// A token's text with SentencePiece's word marker as a space.
    static func piece(_ token: TokenTiming) -> String {
        token.token.replacingOccurrences(of: "\u{2581}", with: " ")
    }

    /// The tokens a window decoded after its lead-in: those emitted before
    /// `leadIn` belong to the previous window's sentence. Emission can run a
    /// little late, so a straggler from that sentence is dropped up to the
    /// first capitalised word — a cut is always made before one.
    static func afterLeadIn(_ tokens: [TokenTiming], leadIn: Double) -> [TokenTiming] {
        guard leadIn > 0 else { return tokens }
        let timed = tokens.drop { $0.startTime < leadIn }
        guard let start = timed.prefix(4).firstIndex(where: {
            let word = piece($0)
            return word.first == " " && word.dropFirst().first?.isUppercase == true
        }) else { return Array(timed) }
        return Array(timed[start...])
    }

    /// Transcribe `samples` window by window. `window` decodes at most
    /// `windowSamples`; `whole` is the engine's own long-audio path, used for
    /// the rest of the audio when a window has no sentence end to cut at —
    /// never worse than before.
    ///
    /// `leadIn` starts every window after the first that many seconds before
    /// its cut, and discards what was decoded there. Parakeet Unified drops
    /// the first word of a window that starts on it ("Everyone who tried" →
    /// "Who tried", 7 of 10 readings); Ultra does not, and takes 0.
    static func transcribe(
        _ samples: [Float],
        leadIn: Double = 0,
        window: ([Float]) async throws -> Decoded,
        whole: ([Float]) async throws -> String
    ) async throws -> String {
        var pieces: [String] = []
        var offset = 0
        while offset < samples.count {
            let lead = offset == 0 ? 0 : min(Int(leadIn * sampleRate), offset)
            let start = offset - lead
            let end = min(start + windowSamples, samples.count)
            let decoded = try await window(Array(samples[start..<end]))
            let tokens = afterLeadIn(decoded.tokens, leadIn: Double(lead) / sampleRate)
            if end == samples.count {
                pieces.append(lead == 0 ? decoded.text : tokens.map(piece).joined())
                break
            }
            guard let cut = cut(in: tokens, windowSeconds: Double(end - start) / sampleRate) else {
                pieces.append(try await whole(Array(samples[offset...])))
                break
            }
            pieces.append(tokens[0...cut.through].map(piece).joined())
            offset = start + Int(cut.at * sampleRate)
        }
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
