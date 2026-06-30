import Foundation
import AVFoundation
import Gemma4Swift
import MLX
import MLXLMCommon

/// Wrapper for Google's Gemma 4 E2B multimodal model (audio → text) running
/// on-device via MLX Swift. Unlike Parakeet/Whisper, Gemma is a single model
/// that does ASR *and* produces clean, punctuated text in one shot, so the
/// transcription pipeline treats it as having native punctuation.
///
/// EXPERIMENTAL. Audio is capped at 30s per clip (Conformer encoder, 750 tokens).
/// The weights (~3.6 GB for E2B 4-bit) download on first load via swift-transformers.
///
/// Implementation note: `Gemma4Pipeline` is `@MainActor` and exposes no audio
/// entry point (its `chat*` methods are text/image only, and its `ModelContainer`
/// is private). So we hold the `ModelContainer` ourselves — loaded via the same
/// public helpers the pipeline uses — and drive the audio generate loop directly,
/// mirroring `gemma4-cli`'s E2B multimodal path.
actor GemmaEngine {
    static let shared = GemmaEngine()

    /// The model to use. E2B 4-bit is the smallest audio-capable Gemma 4.
    private static let model: Gemma4Pipeline.Model = .e2b4bit

    private var container: ModelContainer?
    private var isLoaded = false

    private init() {}

    /// Tracks whether the model finished downloading at least once. Driven off a
    /// successful load rather than a cache path, since Gemma4Swift/swift-transformers
    /// manage their own Hub cache location.
    private static let downloadedKey = "gemmaE2BDownloaded"

    // MARK: - Model Storage

    nonisolated static func isModelDownloaded() -> Bool {
        Gemma4ModelCache.isDownloaded(model) || UserDefaults.standard.bool(forKey: downloadedKey)
    }

    /// On-disk location of the E2B weights in Gemma4Swift's own model cache.
    nonisolated static var modelDirectory: URL {
        Gemma4ModelCache.localPath(for: model) ?? Gemma4ModelCache.modelsDirectory
    }

    nonisolated static func deleteModel() throws {
        UserDefaults.standard.set(false, forKey: downloadedKey)
        guard let dir = Gemma4ModelCache.localPath(for: model),
              FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
        PushLogger.log("GemmaEngine: Model cache deleted from \(dir.path)")
    }

    // MARK: - Public API

    /// Load (and download if needed) the Gemma 4 E2B 4-bit model.
    /// `progress` reports download fraction in 0...1.
    func loadModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if isLoaded { return }

        PushLogger.log("GemmaEngine: Loading Gemma 4 E2B (4-bit, audio)...")

        do {
            // 1. Download weights if they aren't cached yet (~3.6 GB).
            if !Gemma4ModelCache.isDownloaded(Self.model) {
                PushLogger.log("GemmaEngine: Downloading model weights...")
                _ = try await Gemma4ModelDownloader.download(Self.model) { p in
                    progress?(p.fraction)
                }
            } else {
                progress?(1.0)
            }

            // 2. Resolve the local path and load a multimodal ModelContainer.
            guard let localPath = Gemma4ModelCache.localPath(for: Self.model) else {
                throw GemmaEngineError.loadFailed("Model not found in cache after download")
            }
            await Gemma4Registration.register(multimodal: true)
            let loaded = try await loadModelContainer(from: localPath, using: Gemma4TokenizerLoader())

            self.container = loaded
            self.isLoaded = true
            UserDefaults.standard.set(true, forKey: Self.downloadedKey)
            PushLogger.log("GemmaEngine: ✅ Model loaded successfully")
        } catch {
            PushLogger.log("GemmaEngine: ❌ Failed to load model: \(error)")
            throw GemmaEngineError.loadFailed(error.localizedDescription)
        }
    }

    func unloadModel() {
        container = nil
        isLoaded = false
        MLX.Memory.clearCache()
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
        guard let container else {
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

        // 1. Preprocess audio → PCM chunks ready for embed_audio.
        let audio = try await Gemma4AudioProcessor.processAudio(url: wavURL)
        guard audio.numTokens > 0 else { throw GemmaEngineError.emptyAudio }
        PushLogger.log("GemmaEngine: Transcribing \(floats.count) samples (\(audio.numTokens) audio tokens)...")

        let prompt = "Transcribe the following speech into text. Output only the transcription, with no extra commentary."
        let numAudioTokens = audio.numTokens
        // MLXArray isn't Sendable; the features are produced here and only read
        // inside the container action, so the unsafe capture is sound.
        nonisolated(unsafe) let audioFeatures = audio.features
        nonisolated(unsafe) let audioMask = audio.mask

        // 2. Run generation against the model context (mirrors gemma4-cli's E2B
        //    multimodal path, using MLXLMCommon's native streaming generate).
        let text = try await container.perform { context -> String in
            // a. Build the prompt with an <|audio|> placeholder + chat template.
            let content = "<|audio|>\n\(prompt)"
            let messages: [[String: String]] = [["role": "user", "content": content]]
            var ids = try context.tokenizer.applyChatTemplate(messages: messages)

            // b. Expand the audio placeholder → boa + audio_token × N + eoa.
            let audioTokenId = Int(Gemma4Processor.audioTokenId)
            let boaTokenId = Int(Gemma4Processor.boaTokenId)
            let eoaTokenId = Int(Gemma4Processor.eoaTokenId)
            var expanded: [Int] = []
            for tid in ids {
                if tid == audioTokenId {
                    expanded.append(boaTokenId)
                    for _ in 0 ..< numAudioTokens { expanded.append(audioTokenId) }
                    expanded.append(eoaTokenId)
                } else {
                    expanded.append(tid)
                }
            }
            ids = expanded

            // c. Inject audio features — consumed on the first forward of prefill.
            guard let model = context.model as? Gemma4MultimodalLLMModel else {
                throw GemmaEngineError.loadFailed("Loaded model is not multimodal (audio unsupported)")
            }
            model.pendingAudioFeatures = audioFeatures
            model.pendingAudioMask = audioMask

            // d. Greedy generation via the native TokenIterator.
            let lmInput = LMInput(tokens: MLXArray(ids.map { Int32($0) }))
            let params = GenerateParameters(maxTokens: 512, temperature: 0.0, topP: 0.95)
            let stream = try MLXLMCommon.generate(input: lmInput, parameters: params, context: context)
            var out = ""
            for await generation in stream {
                switch generation {
                case .chunk(let chunk): out += chunk
                case .info, .toolCall: break
                }
            }
            return out
        }

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
