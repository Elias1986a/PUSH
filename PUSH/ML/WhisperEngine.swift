import Foundation
import WhisperKit

/// Wrapper for WhisperKit speech-to-text engine
actor WhisperEngine {
    static let shared = WhisperEngine()

    private var whisperKit: WhisperKit?
    private var isLoaded = false
    private var currentModel: String?

    private init() {}

    // MARK: - Model Names

    /// Map our model enum to WhisperKit model names
    private func whisperKitModelName(for model: AppState.WhisperModel) -> String {
        switch model {
        case .tiny: return "openai_whisper-tiny.en"
        case .base: return "openai_whisper-base.en"
        case .small: return "openai_whisper-small.en"
        }
    }

    // MARK: - Public API

    /// Load the Whisper model (downloads if needed)
    func loadModel(_ model: AppState.WhisperModel = .base) async throws {
        let modelName = whisperKitModelName(for: model)

        // Skip if already loaded with same model
        if isLoaded && currentModel == modelName {
            return
        }

        print("WhisperEngine: Loading model \(modelName)...")

        do {
            // WhisperKit automatically downloads the model if not present
            let config = WhisperKitConfig(model: modelName)
            whisperKit = try await WhisperKit(config)

            isLoaded = true
            currentModel = modelName
            print("WhisperEngine: Model loaded successfully")
        } catch {
            print("WhisperEngine: Failed to load model: \(error)")
            throw WhisperError.loadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model
    func unloadModel() {
        whisperKit = nil
        isLoaded = false
        currentModel = nil
        print("WhisperEngine: Model unloaded")
    }

    /// Transcribe audio data to text
    func transcribe(audioData: Data) async throws -> String {
        // Load default model if not loaded
        if !isLoaded {
            let selectedModel = await MainActor.run { AppState.shared.selectedWhisperModel }
            try await loadModel(selectedModel)
        }

        guard let whisper = whisperKit else {
            throw WhisperError.notInitialized
        }

        // Convert audio data to float array
        let floatArray = audioDataToFloatArray(audioData)

        guard !floatArray.isEmpty else {
            throw WhisperError.emptyAudio
        }

        print("WhisperEngine: Transcribing \(floatArray.count) samples...")

        // Transcribe
        let results = try await whisper.transcribe(audioArray: floatArray)

        // Combine all segments
        let text = results.compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("WhisperEngine: Transcription complete: \(text)")
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
