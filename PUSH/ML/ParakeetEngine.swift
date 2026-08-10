import Foundation
import FluidAudio

/// Wrapper for FluidAudio/Parakeet TDT v2 speech-to-text engine (English-only)
actor ParakeetEngine {
    static let shared = ParakeetEngine()

    private var asrManager: AsrManager?
    private var isLoaded = false

    private init() {}

    // MARK: - Model Storage

    /// FluidAudio's default model directory for Parakeet v2
    nonisolated static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FluidAudio/Models/parakeet-tdt-0.6b-v2", isDirectory: true)
    }

    /// Check if the Parakeet v2 model has been downloaded
    nonisolated static func isModelDownloaded() -> Bool {
        let dir = modelDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.contains { $0.hasSuffix(".mlmodelc") }
    }

    /// Delete the downloaded Parakeet model to free disk space
    nonisolated static func deleteModel() throws {
        let dir = modelDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
            PushLogger.log("ParakeetEngine: Model deleted from \(dir.path)")
        }
    }

    // MARK: - Public API

    /// Load the Parakeet TDT v2 model (downloads to FluidAudio's default location if needed)
    func loadModel() async throws {
        if isLoaded { return }

        PushLogger.log("ParakeetEngine: Loading Parakeet TDT v2 (English-only)...")

        do {
            let loadedModels = try await AsrModels.downloadAndLoad(
                version: .v2
            )

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
        isLoaded = false
        PushLogger.log("ParakeetEngine: Model unloaded")
    }

    /// Warm up the model
    func warmup() async {
        PushLogger.log("ParakeetEngine: Starting warmup...")
        let startTime = Date()

        do {
            try await loadModel()

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

        let start = Date()
        let text = try await transcribeFloats(floatArray)
        let elapsed = Date().timeIntervalSince(start)

        // Same format as ParakeetUnifiedEngine so the two are directly
        // comparable in an A/B. Duration + timing only — never transcript text.
        PushLogger.log(String(
            format: "ParakeetEngine: Transcribed %.2fs audio in %.3fs (%d chars)",
            Double(floatArray.count) / 16000.0, elapsed, text.count))
        return text
    }

    // MARK: - Private

    private func transcribeFloats(_ floatArray: [Float]) async throws -> String {
        guard let manager = asrManager else {
            throw ParakeetEngineError.notInitialized
        }

        // A fresh decoder state per utterance: each dictation is independent,
        // so no RNNT context should carry over from the previous one.
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(floatArray, decoderState: &decoderState)
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
