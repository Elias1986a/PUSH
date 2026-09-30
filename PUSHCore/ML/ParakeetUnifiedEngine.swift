import Foundation
import FluidAudio

/// Wrapper for FluidAudio's Parakeet Unified 0.6B (FastConformer-RNNT, English).
///
/// Kept as a separate engine from `ParakeetEngine` (Ultra) so both can be
/// selected side by side and compared on real dictation, rather than swapping
/// one for the other on the strength of published benchmarks.
///
/// Uses the offline full-attention 15s encoder, which FluidAudio reports at
/// 1.82% WER on LibriSpeech test-clean (vs 2.15% for the chunked streaming
/// export), and which emits punctuation and capitalization.
public actor ParakeetUnifiedEngine {
    public static let shared = ParakeetUnifiedEngine()

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
    public nonisolated static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
    }

    /// The repo holds two ~600 MB encoders — offline (this engine) and
    /// streaming (`ParakeetStreamingEngine`) — plus a few MB of decoder and
    /// joint both use. FluidAudio downloads each mode's encoder only when that
    /// mode loads, so "downloaded" and "delete" are per encoder, not per folder.
    public nonisolated static let offlineEncoderFile = ModelNames.ParakeetUnified.offlineEncoderFile(precision: .int8)
    public nonisolated static let streamingEncoderFile = ModelNames.ParakeetUnified.streamingEncoderFile(
        precision: .int8, contextSuffix: UnifiedConfig().contextSuffix)
    nonisolated static let sharedFiles = [
        ModelNames.ParakeetUnified.decoderFile, ModelNames.ParakeetUnified.jointDecisionFile,
    ]

    /// Whether `encoder` and the shared files it needs are on disk.
    public nonisolated static func hasMode(encoder: String, in dir: URL = modelDirectory) -> Bool {
        ([encoder] + sharedFiles).allSatisfy {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    public nonisolated static func isModelDownloaded() -> Bool {
        hasMode(encoder: offlineEncoderFile)
    }

    public nonisolated static func deleteModel() throws {
        try deleteMode(encoder: offlineEncoderFile, keepingIfPresent: streamingEncoderFile)
    }

    /// Remove one mode's encoder; remove the whole folder (shared files
    /// included) only once the other mode's encoder is gone too.
    nonisolated static func deleteMode(
        encoder: String, keepingIfPresent other: String, in dir: URL = modelDirectory
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return }
        if fm.fileExists(atPath: dir.appendingPathComponent(other).path) {
            let file = dir.appendingPathComponent(encoder)
            if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            PushLogger.log("ParakeetUnified: deleted \(encoder), kept the other mode")
        } else {
            try fm.removeItem(at: dir)
            PushLogger.log("ParakeetUnified: deleted \(dir.path)")
        }
    }

    /// Bytes this mode occupies: its encoder plus the shared files.
    public nonisolated static func modeSize(encoder: String) -> Double {
        ([encoder] + sharedFiles).reduce(0) { total, name in
            total + directoryBytes(modelDirectory.appendingPathComponent(name))
        }
    }

    private nonisolated static func directoryBytes(_ url: URL) -> Double {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Double = 0
        for case let f as URL in e {
            total += Double((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: - Public API

    public func loadModel() async throws {
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

    public func unloadModel() {
        manager = nil
        isLoaded = false
        PushLogger.log("ParakeetUnifiedEngine: Model unloaded")
    }

    public func warmup() async {
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

    public func transcribe(audioData: Data) async throws -> String {
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
        // Past one encoder window, cut at sentence ends (see `SentenceAlignedWindows`).
        let text = floatArray.count <= SentenceAlignedWindows.windowSamples
            ? try await manager.transcribe(floatArray)
            : try await SentenceAlignedWindows.transcribe(
                floatArray,
                leadIn: 1.0,
                window: { chunk in
                    let result = try await manager.transcribeWithTimings(chunk)
                    return .init(text: result.text, tokens: result.tokenTimings)
                },
                whole: { try await manager.transcribe($0) })
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
