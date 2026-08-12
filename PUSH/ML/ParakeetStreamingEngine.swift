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
actor ParakeetStreamingEngine {
    static let shared = ParakeetStreamingEngine()

    private var manager: StreamingUnifiedAsrManager?
    private var isLoaded = false

    /// True between `beginUtterance()` and `finishUtterance()`, i.e. when live
    /// samples are arriving and `transcribe(audioData:)` should use them
    /// instead of re-transcribing the recorded buffer.
    private var isStreaming = false
    private var fedSampleCount = 0

    /// Last partial handed to `AppState`, so chunks that decode no new tokens
    /// don't cost a main-actor hop (most mic buffers decode nothing).
    private var publishedPartial = ""

    private static let sampleRate: Double = 16000

    private init() {}

    nonisolated static var modelDirectory: URL {
        // Same model bundle as the offline Unified engine.
        ParakeetUnifiedEngine.modelDirectory
    }

    nonisolated static func isModelDownloaded() -> Bool {
        ParakeetUnifiedEngine.isModelDownloaded()
    }

    // MARK: - Lifecycle

    func loadModel() async throws {
        if isLoaded { return }

        PushLogger.log("ParakeetStreamingEngine: Loading streaming Parakeet Unified...")
        do {
            let manager = StreamingUnifiedAsrManager()
            try await manager.loadModels()
            self.manager = manager
            isLoaded = true
            PushLogger.log("ParakeetStreamingEngine: ✅ Model loaded successfully")
        } catch {
            PushLogger.log("ParakeetStreamingEngine: ❌ Failed to load model: \(error)")
            throw ParakeetEngineError.loadFailed(error.localizedDescription)
        }
    }

    func unloadModel() {
        manager = nil
        isLoaded = false
        isStreaming = false
        PushLogger.log("ParakeetStreamingEngine: Model unloaded")
    }

    func warmup() async {
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
    func beginUtterance() async {
        // Clear ahead of the guard: the pill must never carry the previous
        // take's text into a new one, even when streaming isn't available.
        await publish("")

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
    func feed(_ samples: [Float]) async {
        guard isStreaming, let manager else { return }
        guard let buffer = Self.makeBuffer(from: samples) else { return }
        do {
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
            fedSampleCount += samples.count
            // The transcript is append-only, so the pill never has to un-say a
            // word — each read is the previous one plus whatever just decoded.
            await publish(manager.getPartialTranscript())
        } catch {
            PushLogger.log("ParakeetStreamingEngine: feed failed, falling back to batch: \(error)")
            isStreaming = false
        }
    }

    /// Hand the running transcript to the pill. Never logged — this is
    /// transcript text, which stays out of PushLogger by policy.
    private func publish(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != publishedPartial else { return }
        publishedPartial = trimmed
        await MainActor.run { AppState.shared.liveTranscript = trimmed }
    }

    // MARK: - Transcription

    func transcribe(audioData: Data) async throws -> String {
        if !isLoaded {
            try await loadModel()
        }
        guard let manager else { throw ParakeetEngineError.notInitialized }

        let start = Date()

        if isStreaming, fedSampleCount > 0 {
            // Live path: audio already went in during recording; just flush.
            isStreaming = false
            let text = try await manager.finish()
            // The trailing chunk only decodes here, so publish once more —
            // otherwise the pill's last frame is missing the final words.
            await publish(text)
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
