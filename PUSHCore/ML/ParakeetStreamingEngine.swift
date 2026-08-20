import Foundation
import AVFoundation
import FluidAudio

/// SPIKE: streaming transcription with Parakeet Unified's chunked-attention
/// encoder. Audio is fed in while you speak instead of transcribed after you
/// release, so latency after release is roughly the final chunk rather than
/// the whole utterance.
///
/// Trade-off to evaluate, in FluidAudio's own numbers: the chunked streaming
/// export is 2.15% WER vs 1.82% for the offline encoder `ParakeetUnifiedEngine`
/// uses. So this may give back the accuracy that won the offline A/B.
///
/// Falls back to transcribing the whole buffer if it was never fed live, so
/// `transcribe(audioData:)` still works standalone.
public actor ParakeetStreamingEngine {
    public static let shared = ParakeetStreamingEngine()

    /// Called with each partial transcript while the user is still speaking.
    ///
    /// The engine used to write `AppState.shared.livePartialText` directly, along with
    /// the two guards deciding whether the preview should show at all. Those are the
    /// app's questions, not the engine's — the app installs a handler that asks them,
    /// and the comparison tool installs none.
    public var onPartial: (@Sendable (String) -> Void)?

    public func setOnPartial(_ handler: (@Sendable (String) -> Void)?) {
        onPartial = handler
    }

    private var manager: StreamingUnifiedAsrManager?
    private var isLoaded = false

    /// True between `beginUtterance()` and `finishUtterance()`, i.e. when live
    /// samples are arriving and `transcribe(audioData:)` should use them
    /// instead of re-transcribing the recorded buffer.
    private var isStreaming = false
    private var fedSampleCount = 0

    private static let sampleRate: Double = 16000

    private init() {}

    public nonisolated static var modelDirectory: URL {
        // Same model bundle as the offline Unified engine.
        ParakeetUnifiedEngine.modelDirectory
    }

    public nonisolated static func isModelDownloaded() -> Bool {
        ParakeetUnifiedEngine.isModelDownloaded()
    }

    // MARK: - Lifecycle

    public func loadModel() async throws {
        if isLoaded { return }

        PushLogger.log("ParakeetStreamingEngine: Loading streaming Parakeet Unified...")
        do {
            let manager = StreamingUnifiedAsrManager()
            try await manager.loadModels()
            // Feed the rough in-flight transcript to the pill. Fires off-main
            // roughly once per 1.04s chunk, so it hops to the main actor to
            // publish. Display only — this text is never injected or logged.
            let onPartial = self.onPartial
            await manager.setPartialTranscriptCallback { partial in
                onPartial?(partial)
            }
            self.manager = manager
            isLoaded = true
            PushLogger.log("ParakeetStreamingEngine: ✅ Model loaded successfully")
        } catch {
            PushLogger.log("ParakeetStreamingEngine: ❌ Failed to load model: \(error)")
            throw ParakeetEngineError.loadFailed(error.localizedDescription)
        }
    }

    public func unloadModel() {
        manager = nil
        isLoaded = false
        isStreaming = false
        PushLogger.log("ParakeetStreamingEngine: Model unloaded")
    }

    public func warmup() async {
        PushLogger.log("ParakeetStreamingEngine: Starting warmup...")
        let start = Date()
        do {
            try await loadModel()
            try await manager?.reset()
            let elapsed = Date().timeIntervalSince(start)
            PushLogger.log("ParakeetStreamingEngine: ✅ Warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("ParakeetStreamingEngine: Warmup failed: \(error)")
        }
    }

    // MARK: - Live streaming

    /// Called when recording starts. Safe to call when the model isn't loaded —
    /// it simply won't stream, and transcription falls back to the whole buffer.
    public func beginUtterance() async {
        guard isLoaded, let manager else { return }
        do {
            try await manager.reset()
            fedSampleCount = 0
            isStreaming = true
        } catch {
            PushLogger.log("ParakeetStreamingEngine: reset failed, falling back to batch: \(error)")
            isStreaming = false
        }
    }

    /// Feed mic samples as they arrive. Errors demote to batch mode rather than
    /// failing the recording — dictation must never be lost to a spike.
    public func feed(_ samples: [Float]) async {
        guard isStreaming, let manager else { return }
        guard let buffer = Self.makeBuffer(from: samples) else { return }
        do {
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
            fedSampleCount += samples.count
        } catch {
            PushLogger.log("ParakeetStreamingEngine: feed failed, falling back to batch: \(error)")
            isStreaming = false
        }
    }

    // MARK: - Transcription

    public func transcribe(audioData: Data) async throws -> String {
        if !isLoaded {
            try await loadModel()
        }
        guard let manager else { throw ParakeetEngineError.notInitialized }

        let start = Date()

        if isStreaming, fedSampleCount > 0 {
            // Live path: audio already went in during recording; just flush.
            isStreaming = false
            let text = try await manager.finish()
            let elapsed = Date().timeIntervalSince(start)
            PushLogger.log(String(
                format: "ParakeetStreamingEngine: Streamed %.2fs audio, finalized in %.3fs (%d chars)",
                Double(fedSampleCount) / Self.sampleRate, elapsed, text.count))
            fedSampleCount = 0
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Fallback: never fed live, so push the whole buffer through at once.
        let samples = Self.floatArray(from: audioData)
        guard !samples.isEmpty else { throw ParakeetEngineError.emptyAudio }

        try await manager.reset()
        if let buffer = Self.makeBuffer(from: samples) {
            try await manager.appendAudio(buffer)
        }
        let text = try await manager.finish()
        let elapsed = Date().timeIntervalSince(start)
        PushLogger.log(String(
            format: "ParakeetStreamingEngine: Batch fallback %.2fs audio in %.3fs (%d chars)",
            Double(samples.count) / Self.sampleRate, elapsed, text.count))
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private static func makeBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData
        else { return nil }

        samples.withUnsafeBufferPointer { source in
            channel[0].update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    private static func floatArray(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            for i in 0..<count { out[i] = floats[i] }
        }
        return out
    }
}
