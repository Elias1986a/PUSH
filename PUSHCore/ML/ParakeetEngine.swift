import Foundation
import FluidAudio

/// Wrapper for FluidAudio's batch Parakeet TDT engine, serving Parakeet Ultra.
///
/// Parameterised by `AsrModelVersion` because every TDT build loads through the
/// same `AsrModels.downloadAndLoad(version:)` + `AsrManager` path; TDT v2 used
/// to be the second instance until it was dropped in 8.0.5. Ultra is
/// moondream's post-training of TDT v3 — same tokenizer, window and decoder
/// contract as v3 — so it is multilingual by construction: it auto-detects
/// across the Latin-script European languages, with the decoder's script filter
/// pinned to Latin (see `transcribeFloats`).
public actor ParakeetEngine {
    public static let ultra = ParakeetEngine(version: .ultra, name: "Parakeet Ultra")

    private let version: AsrModelVersion
    /// For log lines only — operational, never transcript text.
    private let name: String
    private var asrManager: AsrManager?
    private var isLoaded = false

    private init(version: AsrModelVersion, name: String) {
        self.version = version
        self.name = name
    }

    // MARK: - Model Storage

    /// Where FluidAudio keeps this model's weights. Asked of FluidAudio rather than
    /// hardcoded so the download and the "is it downloaded?" check cannot disagree.
    public nonisolated var modelDirectory: URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    /// Check if this model has been downloaded
    public nonisolated func isModelDownloaded() -> Bool {
        let dir = modelDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.contains { $0.hasSuffix(".mlmodelc") }
    }

    /// Delete the downloaded model to free disk space
    public nonisolated func deleteModel() throws {
        let dir = modelDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
            PushLogger.log("ParakeetEngine[\(name)]: Model deleted from \(dir.path)")
        }
    }

    // MARK: - Public API

    /// Load the model (downloads to FluidAudio's default location if needed)
    public func loadModel() async throws {
        if isLoaded { return }

        PushLogger.log("ParakeetEngine[\(name)]: Loading...")

        do {
            let loadedModels = try await AsrModels.downloadAndLoad(version: version)

            let manager = AsrManager(config: .default)
            try await manager.loadModels(loadedModels)
            self.asrManager = manager

            isLoaded = true
            PushLogger.log("ParakeetEngine[\(name)]: ✅ Model loaded successfully")
        } catch {
            PushLogger.log("ParakeetEngine[\(name)]: ❌ Failed to load model: \(error)")
            throw ParakeetEngineError.loadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model
    public func unloadModel() {
        asrManager = nil
        isLoaded = false
        PushLogger.log("ParakeetEngine[\(name)]: Model unloaded")
    }

    /// Warm up the model
    public func warmup() async {
        PushLogger.log("ParakeetEngine[\(name)]: Starting warmup...")
        let startTime = Date()

        do {
            try await loadModel()

            let silentAudio = [Float](repeating: 0.0, count: 16000)
            _ = try await transcribeFloats(silentAudio)

            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("ParakeetEngine[\(name)]: ✅ Warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("ParakeetEngine[\(name)]: Warmup failed: \(error)")
        }
    }

    /// Transcribe audio data to text
    public func transcribe(audioData: Data) async throws -> String {
        if !isLoaded {
            PushLogger.log("ParakeetEngine[\(name)]: Not loaded, loading model...")
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
            format: "ParakeetEngine[%@]: Transcribed %.2fs audio in %.3fs (%d chars)",
            name, Double(floatArray.count) / 16000.0, elapsed, text.count))
        return text
    }

    // MARK: - Private

    private func transcribeFloats(_ floatArray: [Float]) async throws -> String {
        guard let manager = asrManager else {
            throw ParakeetEngineError.notInitialized
        }

        // Past one encoder window, cut at sentence ends rather than let
        // FluidAudio's fixed seams start a window mid-sentence.
        guard floatArray.count <= SentenceAlignedWindows.windowSamples else {
            return try await SentenceAlignedWindows.transcribe(
                floatArray,
                window: { chunk in
                    let result = try await Self.decode(chunk, with: manager)
                    return .init(text: result.text, tokens: result.tokenTimings ?? [])
                },
                whole: { try await Self.decode($0, with: manager).text })
        }
        return try await Self.decode(floatArray, with: manager).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ samples: [Float], with manager: AsrManager) async throws -> ASRResult {
        // A fresh decoder state per decode: each dictation — and each window
        // of a long one — is independent, so no RNNT context carries over.
        var decoderState = try TdtDecoderState()
        // Ultra is v3-derived and auto-detects language, so an accented or
        // mumbled English word can surface in Cyrillic. The hint is a *script*
        // filter (Latin vs Cyrillic/Greek), not a language picker.
        return try await manager.transcribe(samples, decoderState: &decoderState, language: .english)
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

public enum ParakeetEngineError: LocalizedError {
    case notInitialized
    case emptyAudio
    case loadFailed(String)

    public var errorDescription: String? {
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
