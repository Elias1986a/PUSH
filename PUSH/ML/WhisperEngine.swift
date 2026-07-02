import Foundation
@preconcurrency import WhisperKit

/// Wrapper for WhisperKit speech-to-text engine
actor WhisperEngine {
    static let shared = WhisperEngine()

    private var whisperKit: WhisperKit?
    private var isLoaded = false
    private var currentModel: String?

    private init() {}

    // MARK: - Model Names

    /// Map our model enum to WhisperKit model names (only for WhisperKit models)
    private static func whisperKitModelName(for model: AppState.WhisperModel) -> String {
        switch model {
        case .base: return "openai_whisper-base.en"
        case .small: return "openai_whisper-small.en"
        case .distilLargeV3: return "distil-whisper_distil-large-v3"
        case .distilLargeV3Turbo: return "distil-whisper_distil-large-v3_turbo"
        case .whisperLargeV3Turbo: return "openai_whisper-large-v3-v20240930_turbo_632MB"
        case .moonshineTiny, .moonshineBase, .parakeetV2: return "" // Not WhisperKit models
        }
    }

    /// Root cache directory passed to WhisperKit as `downloadBase`.
    /// HubApi appends `models/<repo>/<variant>` underneath this.
    /// Lives in Application Support so it's hidden from Finder and not iCloud-synced.
    nonisolated static var downloadBaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("PUSH", isDirectory: true)
            .appendingPathComponent("whisperkit", isDirectory: true)
    }

    nonisolated static func modelFolderURL(for model: AppState.WhisperModel) -> URL {
        let modelName = whisperKitModelName(for: model)
        return downloadBaseURL
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
    }

    /// One-time migration: move any previously downloaded WhisperKit cache from
    /// `~/Documents/huggingface/` (default HubApi location, user-visible + iCloud-synced)
    /// into `downloadBaseURL` under Application Support.
    nonisolated static func migrateLegacyCacheIfNeeded() {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let legacyRoot = documents.appendingPathComponent("huggingface", isDirectory: true)
        guard fm.fileExists(atPath: legacyRoot.path) else { return }

        do {
            try fm.createDirectory(at: downloadBaseURL, withIntermediateDirectories: true)
            let entries = try fm.contentsOfDirectory(at: legacyRoot, includingPropertiesForKeys: nil)
            for entry in entries {
                let dest = downloadBaseURL.appendingPathComponent(entry.lastPathComponent)
                if fm.fileExists(atPath: dest.path) { continue } // don't overwrite newer cache
                try fm.moveItem(at: entry, to: dest)
            }
            // Remove the now-empty legacy dir (ignore if non-empty).
            try? fm.removeItem(at: legacyRoot)
            PushLogger.log("WhisperEngine: ✅ Migrated legacy WhisperKit cache to \(downloadBaseURL.path)")
        } catch {
            PushLogger.log("WhisperEngine: Cache migration skipped: \(error)")
        }
    }

    nonisolated static func isModelDownloaded(_ model: AppState.WhisperModel) -> Bool {
        guard model.engineType == .whisperKit else { return false }
        let folder = modelFolderURL(for: model)
        guard FileManager.default.fileExists(atPath: folder.path) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return contents.contains { $0.hasSuffix(".mlmodelc") }
    }

    // MARK: - Public API

    /// Load the Whisper model (downloads if needed)
    func loadModel(_ model: AppState.WhisperModel = .base) async throws {
        let modelName = Self.whisperKitModelName(for: model)
        guard !modelName.isEmpty else {
            throw WhisperError.loadFailed("\(model.rawValue) is not a WhisperKit model")
        }

        // Skip if already loaded with same model
        if isLoaded && currentModel == modelName {
            return
        }

        PushLogger.log("WhisperEngine: Loading model \(modelName)...")

        // Move any pre-4.1 cache out of ~/Documents/ before WhisperKit looks for it.
        Self.migrateLegacyCacheIfNeeded()
        try? FileManager.default.createDirectory(at: Self.downloadBaseURL, withIntermediateDirectories: true)

        do {
            // WhisperKit automatically downloads the model if not present.
            // downloadBase keeps the HuggingFace cache in Application Support
            // (hidden from Finder, not iCloud-synced) instead of ~/Documents/huggingface/.
            let config = WhisperKitConfig(model: modelName, downloadBase: Self.downloadBaseURL)
            whisperKit = try await WhisperKit(config)

            isLoaded = true
            currentModel = modelName
            PushLogger.log("WhisperEngine: ✅ Model loaded successfully: \(modelName)")
        } catch {
            PushLogger.log("WhisperEngine: ❌ Failed to load model: \(error)")
            throw WhisperError.loadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model
    func unloadModel() {
        whisperKit = nil
        isLoaded = false
        currentModel = nil
        PushLogger.log("WhisperEngine: Model unloaded")
    }

    /// Warm up the model by loading + running a dummy inference (compiles Metal shaders)
    func warmup() async {
        PushLogger.log("WhisperEngine: Starting warmup...")
        let startTime = Date()

        do {
            // Load the model first
            let selectedModel = await MainActor.run { AppState.shared.selectedWhisperModel }
            try await loadModel(selectedModel)

            // Run a dummy inference with 1 second of silence to compile shaders
            await warmupInference()

            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("WhisperEngine: ✅ Full warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("WhisperEngine: Warmup failed: \(error)")
        }
    }

    /// Run a dummy inference to compile Metal shaders (model must already be loaded)
    func warmupInference() async {
        guard let whisper = whisperKit else { return }
        let startTime = Date()
        do {
            let sampleRate = 16000
            let silentAudio = [Float](repeating: 0.0, count: sampleRate)
            _ = try await whisper.transcribe(audioArray: silentAudio)
            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("WhisperEngine: ✅ Shader warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("WhisperEngine: Shader warmup failed: \(error)")
        }
    }

    /// Transcribe audio data to text
    func transcribe(audioData: Data) async throws -> String {
        // Load default model if not loaded
        if !isLoaded {
            let selectedModel = await MainActor.run { AppState.shared.selectedWhisperModel }
            PushLogger.log("WhisperEngine: Not loaded, loading selected model: \(selectedModel)")
            try await loadModel(selectedModel)
        } else {
            PushLogger.log("WhisperEngine: Using already loaded model: \(currentModel ?? "unknown")")
        }

        guard let whisper = whisperKit else {
            throw WhisperError.notInitialized
        }

        // Convert audio data to float array
        let floatArray = audioDataToFloatArray(audioData)

        guard !floatArray.isEmpty else {
            throw WhisperError.emptyAudio
        }

        PushLogger.log("WhisperEngine: Transcribing \(floatArray.count) samples...")

        // Transcribe
        let results = try await whisper.transcribe(audioArray: floatArray)

        // Combine all segments
        let text = results.compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        PushLogger.log("WhisperEngine: Transcription complete (\(text.count) chars)")
        return text
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
}

// MARK: - Errors

enum WhisperError: LocalizedError {
    case notInitialized
    case emptyAudio
    case loadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Whisper engine not initialized"
        case .emptyAudio:
            return "No audio data to transcribe"
        case .loadFailed(let reason):
            return "Failed to load Whisper model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
