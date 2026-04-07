import Foundation
import Qwen3ASR

/// Wrapper for Qwen3-ASR speech-to-text engine
actor Qwen3Engine {
    static let shared = Qwen3Engine()

    private var model: Qwen3ASRModel?
    private var isLoaded = false

    private init() {}

    // MARK: - Model Storage

    private static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PUSH/qwen3-asr-models", isDirectory: true)
    }

    nonisolated static func isModelDownloaded() -> Bool {
        let dir = modelDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !contents.isEmpty
    }

    // MARK: - Public API

    /// Load the Qwen3-ASR model (downloads from HuggingFace if needed)
    func loadModel() async throws {
        if isLoaded { return }

        PushLogger.log("Qwen3Engine: Loading Qwen3-ASR 0.6B...")

        do {
            let dir = Self.modelDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let loadedModel = try await Qwen3ASRModel.fromPretrained(
                modelId: "Qwen/Qwen3-ASR-0.6B",
                cacheDirectory: dir
            )
            self.model = loadedModel

            isLoaded = true
            PushLogger.log("Qwen3Engine: ✅ Model loaded successfully")
        } catch {
            PushLogger.log("Qwen3Engine: ❌ Failed to load model: \(error)")
            throw Qwen3EngineError.loadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model
    func unloadModel() {
        model = nil
        isLoaded = false
        PushLogger.log("Qwen3Engine: Model unloaded")
    }

    /// Warm up the model
    func warmup() async {
        PushLogger.log("Qwen3Engine: Starting warmup...")
        let startTime = Date()

        do {
            try await loadModel()

            // Run a short silent audio to warm up
            let silentAudio = [Float](repeating: 0.0, count: 16000)
            _ = try await transcribeFloats(silentAudio)

            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("Qwen3Engine: ✅ Warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("Qwen3Engine: Warmup failed: \(error)")
        }
    }

    /// Transcribe audio data to text
    func transcribe(audioData: Data) async throws -> String {
        if !isLoaded {
            PushLogger.log("Qwen3Engine: Not loaded, loading model...")
            try await loadModel()
        }

        guard model != nil else {
            throw Qwen3EngineError.notInitialized
        }

        let floatArray = audioDataToFloatArray(audioData)
        guard !floatArray.isEmpty else {
            throw Qwen3EngineError.emptyAudio
        }

        PushLogger.log("Qwen3Engine: Transcribing \(floatArray.count) samples...")

        let text = try await transcribeFloats(floatArray)

        PushLogger.log("Qwen3Engine: Transcription complete (\(text.count) chars)")
        return text
    }

    // MARK: - Private

    private func transcribeFloats(_ floatArray: [Float]) async throws -> String {
        guard let loadedModel = model else {
            throw Qwen3EngineError.notInitialized
        }

        let result = try await loadedModel.transcribe(audioArray: floatArray, sampleRate: 16000)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
}

// MARK: - Errors

enum Qwen3EngineError: LocalizedError {
    case notInitialized
    case emptyAudio
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Qwen3-ASR engine not initialized"
        case .emptyAudio:
            return "No audio data to transcribe"
        case .loadFailed(let reason):
            return "Failed to load Qwen3-ASR model: \(reason)"
        }
    }
}
