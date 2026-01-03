import Foundation
import WhisperKit

/// Wrapper for WhisperKit speech-to-text engine
actor WhisperEngine {
    static let shared = WhisperEngine()

    private var whisperKit: WhisperKit?
    private var isLoaded = false

    private init() {}

    // MARK: - Public API

    /// Load the Whisper model
    func loadModel(_ model: AppState.WhisperModel = .base) async throws {
        guard !isLoaded else { return }

        let modelPath = ModelManager.shared.modelPath(for: model.rawValue)

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw WhisperError.modelNotFound(model.rawValue)
        }

        print("WhisperEngine: Loading model from \(modelPath.path)")

        // Initialize WhisperKit with the model
        whisperKit = try await WhisperKit(
            modelFolder: modelPath.deletingLastPathComponent().path,
            computeOptions: .init(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
        )

        isLoaded = true
        print("WhisperEngine: Model loaded successfully")
    }

    /// Unload the current model
    func unloadModel() {
        whisperKit = nil
        isLoaded = false
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
        let text = results.compactMap { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

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
    case modelNotFound(String)
    case notInitialized
    case emptyAudio
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let model):
            return "Whisper model not found: \(model). Please download it in Settings."
        case .notInitialized:
            return "Whisper engine not initialized"
        case .emptyAudio:
            return "No audio data to transcribe"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
