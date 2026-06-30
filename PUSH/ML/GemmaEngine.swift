import Foundation
import AVFoundation
import Gemma4Swift

/// Wrapper for Google's Gemma 4 E2B multimodal model (audio → text) running
/// on-device via MLX Swift. Unlike Parakeet/Whisper, Gemma is a single model
/// that does ASR *and* produces clean, punctuated text in one shot, so the
/// transcription pipeline treats it as having native punctuation.
///
/// EXPERIMENTAL. Audio is capped at 30s per clip (Conformer encoder, 750 tokens).
/// The weights (~3.6 GB for E2B 4-bit) download on first load via swift-transformers.
actor GemmaEngine {
    static let shared = GemmaEngine()

    private var pipeline: Gemma4Pipeline?
    private var isLoaded = false

    private init() {}

    /// Tracks whether the model finished downloading at least once. Driven off a
    /// successful load rather than a cache path, since Gemma4Swift/swift-transformers
    /// manage their own Hub cache location.
    private static let downloadedKey = "gemmaE2BDownloaded"

    // MARK: - Model Storage

    nonisolated static func isModelDownloaded() -> Bool {
        UserDefaults.standard.bool(forKey: downloadedKey)
    }

    /// Best-effort location of the Hugging Face Hub cache used by swift-transformers.
    /// VERIFY on-device — adjust the subpath if the weights land elsewhere.
    nonisolated static var modelDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("huggingface", isDirectory: true)
    }

    nonisolated static func deleteModel() throws {
        UserDefaults.standard.set(false, forKey: downloadedKey)
        // Best-effort cache removal. VERIFY the exact repo subpath on-device.
        let dir = modelDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
            PushLogger.log("GemmaEngine: Model cache deleted from \(dir.path)")
        }
    }

    // MARK: - Public API

    /// Load (and download if needed) the Gemma 4 E2B 4-bit model.
    /// `progress` reports download fraction in 0...1.
    func loadModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if isLoaded { return }

        PushLogger.log("GemmaEngine: Loading Gemma 4 E2B (4-bit, audio)...")

        do {
            let pipe = Gemma4Pipeline()
            try await pipe.load(.e2b4bit, downloadIfNeeded: true) { p in
                progress?(p.fraction)
            }
            self.pipeline = pipe
            self.isLoaded = true
            UserDefaults.standard.set(true, forKey: Self.downloadedKey)
            PushLogger.log("GemmaEngine: ✅ Model loaded successfully")
        } catch {
            PushLogger.log("GemmaEngine: ❌ Failed to load model: \(error)")
            throw GemmaEngineError.loadFailed(error.localizedDescription)
        }
    }

    func unloadModel() {
        pipeline = nil
        isLoaded = false
        PushLogger.log("GemmaEngine: Model unloaded")
    }

    func warmup() async {
        PushLogger.log("GemmaEngine: Starting warmup...")
        do {
            try await loadModel()
            PushLogger.log("GemmaEngine: ✅ Warmup complete")
        } catch {
            PushLogger.log("GemmaEngine: Warmup failed: \(error)")
        }
    }

    /// Transcribe 16 kHz mono Float32 PCM audio to text.
    func transcribe(audioData: Data) async throws -> String {
        if !isLoaded {
            PushLogger.log("GemmaEngine: Not loaded, loading model...")
            try await loadModel()
        }
        guard let pipeline else {
            throw GemmaEngineError.notInitialized
        }

        var floats = audioDataToFloatArray(audioData)
        guard !floats.isEmpty else {
            throw GemmaEngineError.emptyAudio
        }

        // Gemma audio is capped at 30s. Clip to stay within the encoder limit.
        let maxSamples = 30 * 16_000
        if floats.count > maxSamples {
            PushLogger.log("GemmaEngine: Clipping audio to 30s (was \(floats.count) samples)")
            floats = Array(floats[0..<maxSamples])
        }

        let wavURL = try Self.writeWav(samples: floats, sampleRate: 16_000)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let prompt = "Transcribe the following speech into text. Output only the transcription, with no extra commentary."
        PushLogger.log("GemmaEngine: Transcribing \(floats.count) samples...")
        let text = try await pipeline.describe(audioPath: wavURL.path, prompt: prompt)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        PushLogger.log("GemmaEngine: Transcription complete (\(trimmed.count) chars)")
        return trimmed
    }

    // MARK: - Private

    private func audioDataToFloatArray(_ data: Data) -> [Float] {
        let floatCount = data.count / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: floatCount)
        data.withUnsafeBytes { buffer in
            let floats = buffer.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                floatArray[i] = floats[i]
            }
        }
        return floatArray
    }

    /// Write Float32 PCM samples to a temporary mono WAV file for Gemma's audio loader.
    /// If Gemma4Swift rejects float WAV, switch to 16-bit PCM here.
    private static func writeWav(samples: [Float], sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gemma-\(UUID().uuidString).wav")

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw GemmaEngineError.loadFailed("Could not create audio format")
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw GemmaEngineError.loadFailed("Could not allocate audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                channel[0].update(from: src.baseAddress!, count: samples.count)
            }
        }
        try file.write(from: buffer)
        return url
    }
}

// MARK: - Errors

enum GemmaEngineError: LocalizedError {
    case notInitialized
    case emptyAudio
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Gemma engine not initialized"
        case .emptyAudio:
            return "No audio data to transcribe"
        case .loadFailed(let reason):
            return "Failed to load Gemma model: \(reason)"
        }
    }
}
