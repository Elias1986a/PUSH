import Foundation
import FluidAudio

/// Wrapper for FluidAudio/Parakeet TDT v2 speech-to-text engine
actor ParakeetEngine {
    static let shared = ParakeetEngine()

    private var asrManager: AsrManager?
    private var models: AsrModels?
    private var isLoaded = false

    private init() {}

    // MARK: - Model Storage

    private static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PUSH/parakeet-models", isDirectory: true)
    }

    nonisolated static func isModelDownloaded() -> Bool {
        return AsrModels.modelsExist(at: modelDirectory)
    }

    // MARK: - Public API

    /// Load the Parakeet TDT v2 model (downloads if needed)
    func loadModel() async throws {
        if isLoaded { return }

        PushLogger.log("ParakeetEngine: Loading Parakeet TDT v2...")

        do {
            let dir = Self.modelDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let loadedModels = try await AsrModels.downloadAndLoad(
                to: dir,
                version: .v2
            )
            self.models = loadedModels

            let manager = AsrManager(config: .default)
            try await manager.loadModels(loadedModels)
            self.asrManager = manager

            isLoaded = true
            PushLogger.log("ParakeetEngine: ✅ Model loaded successfully")
        } catch {
            PushLogger.log("ParakeetEngine: ❌ Failed to load model: \(error)")
            throw ParakeetEngineError.loadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model
    func unloadModel() {
        asrManager = nil
        models = nil
        isLoaded = false
        PushLogger.log("ParakeetEngine: Model unloaded")
    }

    /// Warm up the model
    func warmup() async {
        PushLogger.log("ParakeetEngine: Starting warmup...")
        let startTime = Date()

        do {
            try await loadModel()

            // Run a short silent audio to warm up
            let silentAudio = [Float](repeating: 0.0, count: 16000)
            _ = try await transcribeFloats(silentAudio)

            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("ParakeetEngine: ✅ Warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("ParakeetEngine: Warmup failed: \(error)")
        }
    }

    /// Transcribe audio data to text
    func transcribe(audioData: Data) async throws -> String {
        if !isLoaded {
            PushLogger.log("ParakeetEngine: Not loaded, loading model...")
            try await loadModel()
        }

        guard asrManager != nil else {
            throw ParakeetEngineError.notInitialized
        }

        let floatArray = audioDataToFloatArray(audioData)
        guard !floatArray.isEmpty else {
            throw ParakeetEngineError.emptyAudio
        }

        PushLogger.log("ParakeetEngine: Transcribing \(floatArray.count) samples...")

        let text = try await transcribeFloats(floatArray)

        PushLogger.log("ParakeetEngine: Transcription complete (\(text.count) chars)")
        return text
    }

    // MARK: - Private

    private func transcribeFloats(_ floatArray: [Float]) async throws -> String {
        guard let manager = asrManager else {
            throw ParakeetEngineError.notInitialized
        }

        let result = try await manager.transcribe(floatArray, source: .system)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

enum ParakeetEngineError: LocalizedError {
    case notInitialized
    case emptyAudio
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Parakeet engine not initialized"
        case .emptyAudio:
            return "No audio data to transcribe"
        case .loadFailed(let reason):
            return "Failed to load Parakeet model: \(reason)"
        }
    }
}
