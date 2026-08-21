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
        onResult: @MainActor (EngineRun) -> Void
    ) async {
        for model in models {
            let run = await measure(model: model, audio: audio)
            await onResult(run)
        }
    }

    private static func measure(model: WhisperModel, audio: Data) async -> EngineRun {
        do {
            // Load first, then start the clock. Model loading is a one-time cost that
            // says nothing about how fast an engine transcribes, and whichever engine
            // the app happened to have warm would otherwise win every run.
            try await load(model)

            let start = Date()
            let raw = try await TranscriptionPipeline.transcribe(audioData: audio, using: model)
            let seconds = Date().timeIntervalSince(start)

            return EngineRun(
                engine: model.displayName,
                raw: raw,
                final: TranscriptionPipeline.postProcess(
                    raw, hasNativePunctuation: model.hasNativePunctuation),
                seconds: seconds,
                failed: false)
        } catch {
            // Surfaced rather than swallowed: an engine that failed and an engine that
            // heard silence look identical if failures come back as empty text.
            return EngineRun(
                engine: model.displayName,
                raw: "⚠️ \(error.localizedDescription)",
                final: "⚠️ \(error.localizedDescription)",
                seconds: 0,
                failed: true)
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
