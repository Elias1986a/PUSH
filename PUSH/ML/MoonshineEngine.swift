import Foundation
import MoonshineVoice

/// Wrapper for Moonshine speech-to-text engine
actor MoonshineEngine {
    static let shared = MoonshineEngine()

    private var transcriber: Transcriber?
    private var isLoaded = false
    private var currentModel: AppState.WhisperModel?

    private init() {}

    // MARK: - Model Paths

    /// Bundled model path inside the Moonshine framework (Tiny only)
    private static func bundledModelPath(name: String) -> String? {
        guard let bundle = Transcriber.frameworkBundle,
              let resourcePath = bundle.resourcePath else {
            PushLogger.log("MoonshineEngine: Could not find framework bundle")
            return nil
        }
        let path = resourcePath.appending("/test-assets/\(name)")
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
        PushLogger.log("MoonshineEngine: Bundled model not found at \(path)")
        return nil
    }

    /// Downloaded model directory in Application Support
    private static func downloadedModelDir(name: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("PUSH/moonshine-models", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// Check if a downloaded model has all required files
    nonisolated static func isModelDownloaded(_ model: AppState.WhisperModel) -> Bool {
        guard model.isMoonshine else { return false }
        if model == .moonshineTiny { return true } // Bundled
        let dir = downloadedModelDir(name: "base-en")
        let required = ["decoder_model_merged.ort", "encoder_model.ort", "tokenizer.bin"]
        return required.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    /// Resolve the model path — bundled for Tiny, downloaded for Base
    private static func resolveModelPath(for model: AppState.WhisperModel) -> String? {
        switch model {
        case .moonshineTiny:
            return bundledModelPath(name: "tiny-en")
        case .moonshineBase:
            let dir = downloadedModelDir(name: "base-en")
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("encoder_model.ort").path) {
                return dir.path
            }
            return nil
        default:
            return nil
        }
    }

    private static func moonshineArch(for model: AppState.WhisperModel) -> ModelArch {
        switch model {
        case .moonshineBase: return .base
        default: return .tiny
        }
    }

    // MARK: - Model Download

    /// Download Moonshine Base model files from GitHub LFS
    func downloadBaseModel() async throws {
        let dir = Self.downloadedModelDir(name: "base-en")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // LFS files use media.githubusercontent.com; small files use raw.githubusercontent.com
        let lfsBaseURL = "https://media.githubusercontent.com/media/moonshine-ai/moonshine/main/examples/ios/Transcriber/models/base-en"
        let rawBaseURL = "https://raw.githubusercontent.com/moonshine-ai/moonshine/main/examples/ios/Transcriber/models/base-en"
        let files = ["decoder_model_merged.ort", "encoder_model.ort", "tokenizer.bin"]

        for file in files {
            let dest = dir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: dest.path) {
                PushLogger.log("MoonshineEngine: \(file) already exists, skipping")
                continue
            }

            // tokenizer.bin is a regular git file, not LFS
            let base = (file == "tokenizer.bin") ? rawBaseURL : lfsBaseURL
            guard let url = URL(string: "\(base)/\(file)") else { continue }

            PushLogger.log("MoonshineEngine: Downloading \(file)...")
            let (tempURL, response) = try await URLSession.shared.download(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw MoonshineEngineError.downloadFailed("HTTP \(code) for \(file)")
            }

            try FileManager.default.moveItem(at: tempURL, to: dest)
            PushLogger.log("MoonshineEngine: ✅ Downloaded \(file)")
        }

        PushLogger.log("MoonshineEngine: ✅ All base model files downloaded")
    }

    // MARK: - Public API

    /// Load the Moonshine model (downloads Base if needed)
    func loadModel(_ model: AppState.WhisperModel) async throws {
        // Skip if already loaded with same model
        if isLoaded && currentModel == model {
            return
        }

        // Unload previous model if switching
        if isLoaded {
            unloadModel()
        }

        PushLogger.log("MoonshineEngine: Loading \(model.displayName)...")

        // Download Base model if needed
        if model == .moonshineBase && !Self.isModelDownloaded(model) {
            PushLogger.log("MoonshineEngine: Base model not found, downloading...")
            await MainActor.run {
                AppState.shared.statusMessage = "Downloading Moonshine Base model..."
            }
            try await downloadBaseModel()
        }

        guard let path = Self.resolveModelPath(for: model) else {
            PushLogger.log("MoonshineEngine: ❌ Could not find model files")
            throw MoonshineEngineError.modelNotFound
        }

        do {
            let arch = Self.moonshineArch(for: model)
            transcriber = try Transcriber(modelPath: path, modelArch: arch)
            isLoaded = true
            currentModel = model
            PushLogger.log("MoonshineEngine: ✅ Model loaded from \(path)")
        } catch {
            PushLogger.log("MoonshineEngine: ❌ Failed to load model: \(error)")
            throw MoonshineEngineError.loadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model
    func unloadModel() {
        transcriber?.close()
        transcriber = nil
        isLoaded = false
        currentModel = nil
        PushLogger.log("MoonshineEngine: Model unloaded")
    }

    /// Run a dummy inference to warm up the engine (model must already be loaded)
    func warmupInference() async {
        guard let engine = transcriber else { return }
        let startTime = Date()
        do {
            let sampleRate: Int32 = 16000
            let silentAudio = [Float](repeating: 0.0, count: Int(sampleRate / 2))
            _ = try engine.transcribeWithoutStreaming(
                audioData: silentAudio,
                sampleRate: sampleRate,
                flags: 0
            )
            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("MoonshineEngine: ✅ Inference warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("MoonshineEngine: Inference warmup failed: \(error)")
        }
    }

    /// Transcribe audio data to text
    func transcribe(audioData: Data) async throws -> String {
        if !isLoaded {
            let activeModel = await MainActor.run { AppState.shared.activeModel }
            PushLogger.log("MoonshineEngine: Not loaded, loading \(activeModel.displayName)...")
            try await loadModel(activeModel)
        }

        guard let engine = transcriber else {
            throw MoonshineEngineError.notInitialized
        }

        // Convert audio data to float array
        let floatArray = audioDataToFloatArray(audioData)

        guard !floatArray.isEmpty else {
            throw MoonshineEngineError.emptyAudio
        }

        PushLogger.log("MoonshineEngine: Transcribing \(floatArray.count) samples...")

        let transcript = try engine.transcribeWithoutStreaming(
            audioData: floatArray,
            sampleRate: 16000,
            flags: 0
        )

        // Combine all lines
        let text = transcript.lines
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        PushLogger.log("MoonshineEngine: Transcription complete (\(text.count) chars)")
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

enum MoonshineEngineError: LocalizedError {
    case notInitialized
    case emptyAudio
    case modelNotFound
    case loadFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Moonshine engine not initialized"
        case .emptyAudio:
            return "No audio data to transcribe"
        case .modelNotFound:
            return "Moonshine model files not found"
        case .loadFailed(let reason):
            return "Failed to load Moonshine model: \(reason)"
        case .downloadFailed(let reason):
            return "Failed to download Moonshine model: \(reason)"
        }
    }
}
