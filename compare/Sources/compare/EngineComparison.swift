import Foundation
import PUSHCore

/// One engine's result for one recording.
struct EngineRun: Codable, Identifiable, Sendable {
    var id = UUID()
    let engine: String
    /// What the model heard, before any post-processing.
    let raw: String
    /// What PUSH would actually paste — `raw` through the same `postProcess` the app runs.
    let final: String
    /// Release → text ready. Model loading is excluded; see `EngineComparison`.
    let seconds: Double
    /// Time spent getting the model ready. Reported separately because it is a one-time
    /// cost that says nothing about engine speed — but it is most of the wall clock on a
    /// first run, and hiding it makes the tool look hung.
    let loadSeconds: Double
    let failed: Bool

    var realtimeFactor: (Double) -> Double { { audio in audio / max(self.seconds, 0.0001) } }
}

/// One recording, run through every available engine.
struct Comparison: Codable, Identifiable, Sendable {
    var id = UUID()
    let date: Date
    let audioSeconds: Double
    var runs: [EngineRun]
    /// Apple's on-device cleanup applied to one engine's raw text, with its own cost.
    /// Kept out of dictation for being too slow; this is where that cost is the point.
    var cleanup: CleanupRun?
    /// Wispr Flow's result for the same utterance, when its hotkey was held too.
    var wispr: WisprRun?
    /// Why there is no Wispr result. Rendered, so an absent row never reads as a bug.
    var wisprAbsence: String?
}

struct CleanupRun: Codable, Sendable {
    let basedOn: String
    let text: String
    let seconds: Double
}

/// Runs one captured buffer through each engine.
enum EngineComparison {

    /// Every model the tool can actually run right now. Whisper and Parakeet variants
    /// are listed only when their weights are already on disk — this tool should never
    /// be the reason a 600 MB download starts.
    static func availableModels() -> [WhisperModel] {
        WhisperModel.selectable.filter { model in
            switch model.engineType {
            case .appleSpeech: return true
            case .whisperKit: return WhisperEngine.isModelDownloaded(model)
            case .moonshine: return MoonshineEngine.isModelDownloaded(model)
            case .parakeet: return ParakeetEngine.isModelDownloaded()
            case .parakeetUnified: return ParakeetUnifiedEngine.isModelDownloaded()
            case .parakeetStreaming: return ParakeetStreamingEngine.isModelDownloaded()
            }
        }
    }

    /// Transcribe `audio` with each model in turn.
    ///
    /// Sequential on purpose. Two engines racing for the Neural Engine would contaminate
    /// each other's timings, and timings are half the point — this is not a live race,
    /// each engine is measured alone.
    static func run(
        audio: Data,
        models: [WhisperModel],
        onPhase: @MainActor (String) -> Void,
        onResult: @MainActor (EngineRun) -> Void
    ) async {
        for model in models {
            await onPhase("Preparing \(model.displayName)…")
            let run = await measure(model: model, audio: audio, onPhase: onPhase)
            await onResult(run)
        }
    }

    private static func measure(
        model: WhisperModel,
        audio: Data,
        onPhase: @MainActor (String) -> Void
    ) async -> EngineRun {
        func failure(_ message: String, load: Double) -> EngineRun {
            // Surfaced rather than swallowed: an engine that failed and an engine that
            // heard silence look identical if failures come back as empty text.
            EngineRun(engine: model.displayName, raw: "⚠️ \(message)", final: "⚠️ \(message)",
                      seconds: 0, loadSeconds: load, failed: true)
        }

        let loadStart = Date()
        do {
            // Load first, then start the clock. Loading is a one-time cost that says
            // nothing about how fast an engine transcribes, and whichever engine the app
            // happened to have warm would otherwise win every run.
            //
            // The first inference is where CoreML actually compiles the model for the
            // Neural Engine — measured at roughly two minutes for Whisper Large v3
            // Turbo's 632 MB. Warming up here keeps that out of the timed pass and,
            // more importantly, lets the UI say what it is waiting for.
            try await withTimeout(.seconds(600)) { try await load(model) }
            await onPhase("Warming up \(model.displayName)… (first run compiles for the Neural Engine and can take minutes)")
            await warmup(model)
        } catch is TimeoutError {
            return failure("gave up loading after 10 minutes", load: Date().timeIntervalSince(loadStart))
        } catch {
            return failure(error.localizedDescription, load: Date().timeIntervalSince(loadStart))
        }
        let loadSeconds = Date().timeIntervalSince(loadStart)

        await onPhase("Transcribing with \(model.displayName)…")
        do {
            let start = Date()
            let raw = try await withTimeout(.seconds(300)) {
                try await TranscriptionPipeline.transcribe(audioData: audio, using: model)
            }
            let seconds = Date().timeIntervalSince(start)

            return EngineRun(
                engine: model.displayName,
                raw: raw,
                final: TranscriptionPipeline.postProcess(
                    raw, hasNativePunctuation: model.hasNativePunctuation),
                seconds: seconds,
                loadSeconds: loadSeconds,
                failed: false)
        } catch is TimeoutError {
            return failure("transcription timed out after 5 minutes", load: loadSeconds)
        } catch {
            return failure(error.localizedDescription, load: loadSeconds)
        }
    }

    /// Run the engine's own warmup so the CoreML/ANE compile happens before the clock
    /// starts. Failures are ignored: a warmup that fails is not a reason to skip the
    /// engine, and the real attempt reports the error properly.
    private static func warmup(_ model: WhisperModel) async {
        switch model.engineType {
        case .whisperKit: await WhisperEngine.shared.warmupInference()
        case .moonshine: await MoonshineEngine.shared.warmupInference()
        case .parakeet: await ParakeetEngine.shared.warmup()
        case .parakeetUnified: await ParakeetUnifiedEngine.shared.warmup()
        case .parakeetStreaming: await ParakeetStreamingEngine.shared.warmup()
        case .appleSpeech:
            if #available(macOS 26, *) { await AppleSpeechEngine.shared.warmup() }
        }
    }

    private struct TimeoutError: Error {}

    /// Bound every engine call. Without this one pathological model hangs the whole run
    /// and every engine behind it never gets a turn.
    private static func withTimeout<T: Sendable>(
        _ limit: Duration,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimeoutError()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimeoutError() }
            return first
        }
    }

    private static func load(_ model: WhisperModel) async throws {
        switch model.engineType {
        case .whisperKit: try await WhisperEngine.shared.loadModel(model)
        case .moonshine: try await MoonshineEngine.shared.loadModel(model)
        case .parakeet: try await ParakeetEngine.shared.loadModel()
        case .parakeetUnified: try await ParakeetUnifiedEngine.shared.loadModel()
        case .parakeetStreaming: try await ParakeetStreamingEngine.shared.loadModel()
        case .appleSpeech:
            guard #available(macOS 26, *) else { throw ComparisonError.needsNewerSystem }
            try await AppleSpeechEngine.shared.loadModel()
        }
    }

    /// Apple's on-device cleanup over one engine's raw text.
    static func cleanup(of raw: String, engine: String) async -> CleanupRun? {
        guard #available(macOS 26, *), AppleTextCleanup.isAvailable else { return nil }
        let start = Date()
        guard let text = await AppleTextCleanup.clean(raw) else {
            return CleanupRun(
                basedOn: engine,
                text: "⚠️ rejected or timed out — PUSH would fall back to the rules",
                seconds: Date().timeIntervalSince(start))
        }
        return CleanupRun(basedOn: engine, text: text, seconds: Date().timeIntervalSince(start))
    }
}

enum ComparisonError: LocalizedError {
    case needsNewerSystem
    var errorDescription: String? { "Requires macOS 26 or later" }
}
