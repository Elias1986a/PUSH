import Foundation

/// Decodes a long dictation while it is still being spoken, so that letting go
/// leaves one short decode rather than the whole recording.
///
/// Built on `SentenceAlignedWindows`: whenever enough undecided audio has
/// arrived, decode it in the background, keep every sentence that is clearly
/// finished — its end at least `endGuardSeconds` before the audio runs out —
/// and move the start of the undecided audio to the pause after it. Each
/// window therefore still starts at a sentence, which is what keeps the
/// punctuation (see that type). On release, `finish` decodes only what is
/// left, usually the last sentence or two.
///
/// Why it matters: decoded after release, a 25 s dictation took two or three
/// windows back to back on a Neural Engine that had idled — and slowed — for
/// the whole of the speech (measured ~0.1 s slower than when busy). Here the
/// engine works while the user talks.
///
/// Only the batch Parakeet engines take part. Streaming already decodes as it
/// hears; Nemotron has its own path. Anything that goes wrong returns nil from
/// `finish`, and the caller transcribes the recording the ordinary way.
public actor LiveDecoder {

    /// Undecided audio needed before a background decode is worth it. Below
    /// this, one decode after release is already fast.
    static let triggerSamples = Int(8 * SentenceAlignedWindows.sampleRate)

    /// New audio needed before retrying a window that had no sentence end to
    /// keep — someone mid-sentence needs a moment to finish it.
    static let retrySamples = Int(2 * SentenceAlignedWindows.sampleRate)

    typealias Window = @Sendable ([Float]) async throws -> SentenceAlignedWindows.Decoded
    typealias Whole = @Sendable ([Float]) async throws -> String

    /// The engine this decoder feeds, so a result is never used for another.
    public nonisolated let model: WhisperModel

    private let window: Window
    private let whole: Whole
    private let leadIn: Double

    private var samples: [Float] = []
    /// Start of the audio that is not text yet.
    private var offset = 0
    private var pieces: [String] = []
    private var inFlight: Task<Void, Never>?
    /// Audio length at the last attempt, so a window without a sentence end
    /// is not re-decoded on every buffer.
    private var attemptedAt = 0
    /// A full window had no sentence end at all; the rest is left to `finish`,
    /// which falls back to the engine's own long path exactly as before.
    private var stuck = false
    private var closed = false

    init(model: WhisperModel, leadIn: Double, window: @escaping Window, whole: @escaping Whole) {
        self.model = model
        self.leadIn = leadIn
        self.window = window
        self.whole = whole
    }

    /// A decoder for `model`, or nil for engines that do not use one.
    public static func make(for model: WhisperModel) -> LiveDecoder? {
        switch model.engineType {
        case .parakeetUltra:
            let engine = ParakeetEngine.ultra
            return LiveDecoder(model: model, leadIn: 0,
                               window: { try await engine.decodeWindow($0) },
                               whole: { try await engine.decodeWhole($0) })
        case .parakeetUnified:
            let engine = ParakeetUnifiedEngine.shared
            return LiveDecoder(model: model, leadIn: ParakeetUnifiedEngine.leadIn,
                               window: { try await engine.decodeWindow($0) },
                               whole: { try await engine.decodeWhole($0) })
        case .parakeetStreaming, .nemotronMultilingual:
            return nil
        }
    }

    /// The audio heard so far, in samples — `finish` checks it against the
    /// recording it is asked to stand in for.
    public var sampleCount: Int { samples.count }

    /// More audio, as the recorder receives it. Cheap: never waits on a decode.
    public func append(_ newSamples: [Float]) {
        guard !closed else { return }
        samples.append(contentsOf: newSamples)
        startPassIfDue()
    }

    private func startPassIfDue() {
        guard !closed, !stuck, inFlight == nil,
              samples.count - offset >= Self.triggerSamples,
              samples.count - attemptedAt >= Self.retrySamples else { return }
        attemptedAt = samples.count
        // Only the window's own audio leaves the actor: a copy of the whole
        // take per pass would be megabytes a minute into a long dictation.
        let from = offset
        let lead = from == 0 ? 0 : min(Int(leadIn * SentenceAlignedWindows.sampleRate), from)
        let base = from - lead
        let slice = Array(samples[base..<min(base + SentenceAlignedWindows.windowSamples, samples.count)])
        let (leadIn, window) = (leadIn, window)
        inFlight = Task {
            let pass = try? await SentenceAlignedWindows.pass(
                slice, from: lead, limit: slice.count, leadIn: leadIn, window: window)
            await self.keep(pass, base: base, from: from)
        }
    }

    /// Keep the finished sentences a pass found, and go again if more audio
    /// is already waiting.
    /// `base` is where the pass's audio sits in the take.
    private func keep(_ pass: SentenceAlignedWindows.Pass?, base: Int, from: Int) {
        inFlight = nil
        guard !closed, let pass, from == offset else { return }
        if let cut = SentenceAlignedWindows.cut(in: pass.tokens, windowSeconds: pass.seconds) {
            pieces.append(pass.text(through: cut.through))
            offset = base + pass.start + Int(cut.at * SentenceAlignedWindows.sampleRate)
        } else if pass.end - pass.start == SentenceAlignedWindows.windowSamples {
            stuck = true
        }
        startPassIfDue()
    }

    /// The whole dictation's text once the user has let go: what was kept
    /// while they spoke, plus the rest decoded now. Nil if this decoder did not
    /// hear the same `expectedSamples` the recorder captured, or anything
    /// failed — the caller then transcribes the recording itself.
    public func finish(expectedSamples: Int) async -> String? {
        closed = true
        await inFlight?.value
        guard samples.count == expectedSamples else { return nil }
        do {
            let rest = try await SentenceAlignedWindows.transcribe(
                samples, from: offset, leadIn: leadIn, window: window, whole: whole)
            return SentenceAlignedWindows.join(pieces + [rest])
        } catch {
            return nil
        }
    }

    /// Stop: the take was cancelled, or its audio is going nowhere.
    public func cancel() {
        closed = true
        inFlight?.cancel()
    }

    /// Replay a recording as if it were being spoken: fed in the recorder's
    /// buffer size, each background pass allowed to finish before the next
    /// buffer (in real time a pass takes ~0.1 s and the next is due 2 s
    /// later), then timed from "release" to text. The compare tool's measure
    /// of what the user waits for.
    public static func replay(_ samples: [Float], model: WhisperModel)
        async -> (text: String, seconds: Double, keptLive: Int)? {
        guard let decoder = make(for: model) else { return nil }
        let buffer = 1_365  // 4096 frames at 48 kHz, resampled to 16 kHz
        var index = 0
        while index < samples.count {
            let end = min(index + buffer, samples.count)
            await decoder.append(Array(samples[index..<end]))
            await decoder.settle()
            index = end
        }
        let kept = await decoder.progress.kept
        let start = Date()
        guard let text = await decoder.finish(expectedSamples: samples.count) else { return nil }
        return (text, Date().timeIntervalSince(start), kept)
    }

    /// Wait for the pass in flight, if any.
    func settle() async {
        while let task = inFlight { await task.value }
    }

    /// How far the live passes got: sentences kept and the seconds of audio
    /// left for `finish`. Operational only, for the log and the compare tool.
    public var progress: (kept: Int, remainingSeconds: Double) {
        (pieces.count, Double(samples.count - offset) / SentenceAlignedWindows.sampleRate)
    }
}
