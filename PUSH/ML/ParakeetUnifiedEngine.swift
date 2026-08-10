import Foundation
import FluidAudio

/// Wrapper for FluidAudio's Parakeet Unified 0.6B (FastConformer-RNNT, English).
///
/// Kept as a separate engine from `ParakeetEngine` (TDT v2) so both can be
/// selected side by side and compared on real dictation, rather than swapping
/// one for the other on the strength of published benchmarks.
///
/// Uses the offline full-attention 15s encoder, which FluidAudio reports at
/// 1.82% WER on LibriSpeech test-clean (vs 2.15% for the chunked streaming
/// export), and which emits punctuation and capitalization.
actor ParakeetUnifiedEngine {
    static let shared = ParakeetUnifiedEngine()

    private var manager: UnifiedAsrManager?
    private var isLoaded = false

    private init() {}

    // MARK: - Model Storage

    /// FluidAudio's model directory for Parakeet Unified.
    ///
    /// Derived from `Repo.folderName` rather than hardcoded: the local folder
    /// is not the HuggingFace repo name (FluidAudio strips the "-coreml"
    /// suffix), and hardcoding it once already produced a false
    /// "Not downloaded" in Settings while the model was loaded and serving.
    nonisolated static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
    }

    nonisolated static func isModelDownloaded() -> Bool {
        let dir = modelDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.contains { $0.hasSuffix(".mlmodelc") }
    }

    nonisolated static func deleteModel() throws {
        let dir = modelDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
            PushLogger.log("ParakeetUnifiedEngine: Model deleted from \(dir.path)")
        }
    }

    // MARK: - Public API

    func loadModel() async throws {
        if isLoaded { return }

        PushLogger.log("ParakeetUnifiedEngine: Loading Parakeet Unified 0.6B (English)...")

        do {
            let manager = UnifiedAsrManager()
            try await manager.loadModels()
            self.manager = manager

            isLoaded = true
            PushLogger.log("ParakeetUnifiedEngine: ✅ Model loaded successfully")
        } catch {
            PushLogger.log("ParakeetUnifiedEngine: ❌ Failed to load model: \(error)")
            throw ParakeetEngineError.loadFailed(error.localizedDescription)
        }
    }

    func unloadModel() {
        manager = nil
        isLoaded = false
        PushLogger.log("ParakeetUnifiedEngine: Model unloaded")
    }

    func warmup() async {
        PushLogger.log("ParakeetUnifiedEngine: Starting warmup...")
        let startTime = Date()

        do {
            try await loadModel()

            let silentAudio = [Float](repeating: 0.0, count: 16000)
            _ = try await transcribeFloats(silentAudio)

            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("ParakeetUnifiedEngine: ✅ Warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("ParakeetUnifiedEngine: Warmup failed: \(error)")
        }
    }

    func transcribe(audioData: Data) async throws -> String {
        if !isLoaded {
            PushLogger.log("ParakeetUnifiedEngine: Not loaded, loading model...")
            try await loadModel()
        }

        let floatArray = audioDataToFloatArray(audioData)
        guard !floatArray.isEmpty else {
            throw ParakeetEngineError.emptyAudio
        }

        let start = Date()
        let text = try await transcribeFloats(floatArray)
        let elapsed = Date().timeIntervalSince(start)

        // Duration + inference time only — never the transcript itself.
        PushLogger.log(String(
            format: "ParakeetUnifiedEngine: Transcribed %.2fs audio in %.3fs (%d chars)",
            Double(floatArray.count) / 16000.0, elapsed, text.count))
        return text
    }

    // MARK: - Private

    private func transcribeFloats(_ floatArray: [Float]) async throws -> String {
        guard let manager else {
            throw ParakeetEngineError.notInitialized
        }
        let text = try await manager.transcribe(floatArray)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
