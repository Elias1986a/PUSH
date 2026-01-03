import Foundation
import SwiftLlama

/// Wrapper for SwiftLlama to run Qwen text formatting
actor QwenEngine {
    static let shared = QwenEngine()

    private var llama: SwiftLlama?
    private var isLoaded = false

    // Qwen formatting prompt
    private let systemPrompt = """
    You are a text formatter. Take the raw speech transcription and output properly formatted text with correct punctuation, capitalization, and paragraph breaks.

    Rules:
    - Fix punctuation (periods, commas, question marks)
    - Capitalize properly (sentences, names, "I")
    - Format numbered lists properly (1. 2. 3.)
    - Use context for homophones (their/there/they're, your/you're, here/hear)
    - Do NOT add, remove, or rephrase words
    - Handle dictation commands: "new line" → newline, "period" → .

    Output ONLY the formatted text, nothing else.
    """

    private init() {}

    // MARK: - Public API

    /// Load the Qwen model
    func loadModel(_ model: AppState.QwenModel = .qwen3_1_7B) async throws {
        guard !isLoaded else { return }

        let modelPath = await ModelManager.shared.modelPath(for: model.rawValue + ".gguf")

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw QwenError.modelNotFound(model.rawValue)
        }

        print("QwenEngine: Loading model from \(modelPath.path)")

        do {
            llama = try SwiftLlama(modelPath: modelPath.path)
            isLoaded = true
            print("QwenEngine: Model loaded successfully")
        } catch {
            throw QwenError.loadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model
    func unloadModel() {
        llama = nil
        isLoaded = false
        print("QwenEngine: Model unloaded")
    }

    /// Format text using Qwen
    func format(text: String) async throws -> String {
        // Load default model if not loaded
        if !isLoaded {
            let selectedModel = await MainActor.run { AppState.shared.selectedQwenModel }
            try await loadModel(selectedModel)
        }

        guard let llama = llama else {
            throw QwenError.notInitialized
        }

        // Build the prompt using SwiftLlama's Prompt struct
        // Qwen uses ChatML format
        let prompt = Prompt(
            type: .chatML,
            systemPrompt: systemPrompt,
            userMessage: text
        )

        print("QwenEngine: Formatting text...")

        do {
            // Use non-streaming mode for simplicity and speed
            let response = try await llama.start(for: prompt)

            let formatted = cleanOutput(response)
            print("QwenEngine: Formatting complete")

            return formatted
        } catch {
            throw QwenError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func cleanOutput(_ text: String) -> String {
        // Remove any special tokens that might have leaked through
        let cleaned = text
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|im_start|>", with: "")
            .replacingOccurrences(of: "assistant", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
}

// MARK: - Errors

enum QwenError: LocalizedError {
    case modelNotFound(String)
    case notInitialized
    case loadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let model):
            return "Qwen model not found: \(model). Please download it in Settings."
        case .notInitialized:
            return "Qwen engine not initialized"
        case .loadFailed(let reason):
            return "Failed to load Qwen: \(reason)"
        case .generationFailed(let reason):
            return "Text generation failed: \(reason)"
        }
    }
}
