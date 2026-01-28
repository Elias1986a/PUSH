import Foundation
import SwiftLlama

/// Generates text predictions using a local LLM via SwiftLlama
@MainActor
final class TextPredictionEngine: @unchecked Sendable {
    static let shared = TextPredictionEngine()

    // MARK: - State

    private(set) var isModelLoaded = false
    private(set) var isProcessing = false
    private(set) var currentPrediction = ""

    private var llama: SwiftLlama?
    private var modelPath: String?

    // MARK: - Configuration

    var maxTokens: Int = 20
    var temperature: Float = 0.2
    var topP: Float = 0.9
    var topK: Int = 40

    /// Personal context that gets injected into the system prompt to personalize predictions
    var personalContext: String = ""

    // MARK: - Model Options

    enum TextModel: String, CaseIterable, Identifiable {
        case tinyLlama = "tinyllama-1.1b-chat-v1.0.Q4_K_M"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tinyLlama: return "TinyLlama 1.1B (638 MB)"
            }
        }

        var filename: String {
            rawValue + ".gguf"
        }
    }

    // MARK: - Errors

    enum PredictionError: Error, LocalizedError {
        case modelNotFound
        case modelLoadFailed(String)
        case predictionFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "Model file not found at expected path"
            case .modelLoadFailed(let msg): return "Model load failed: \(msg)"
            case .predictionFailed(let msg): return "Prediction failed: \(msg)"
            }
        }
    }

    private init() {}

    private func log(_ message: String) {
        print(message)
        let logPath = "/tmp/push_debug.log"
        let timestamp = Date().ISO8601Format()
        let logMessage = "\(timestamp): \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    /// Static log for use from non-MainActor contexts
    nonisolated static func writeLog(_ message: String) {
        let logPath = "/tmp/push_debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "\(timestamp): TextPredictionEngine: \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    // MARK: - Public API

    /// Load a GGUF model from disk (async — heavy init runs off main thread)
    func loadModel(path: String) async throws {
        log("TextPredictionEngine: Loading model from \(path)")

        guard FileManager.default.fileExists(atPath: path) else {
            log("TextPredictionEngine: ERROR - File not found at \(path)")
            throw PredictionError.modelNotFound
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        log("TextPredictionEngine: Model file size: \(fileSize / 1_000_000) MB")

        let capturedTopK = topK
        let capturedTopP = topP
        let capturedTemp = temperature
        let capturedMaxTokens = maxTokens

        // Run heavy model loading off the main thread
        let loadedLlama: SwiftLlama = try await Task.detached {
            let config = Configuration(
                topK: capturedTopK,
                topP: capturedTopP,
                nCTX: 512,
                temperature: capturedTemp,
                batchSize: 512,
                maxTokenCount: capturedMaxTokens
            )

            TextPredictionEngine.writeLog("Initializing SwiftLlama (off main thread)...")
            do {
                let llm = try SwiftLlama(modelPath: path, modelConfiguration: config)
                TextPredictionEngine.writeLog("SwiftLlama init succeeded")
                return llm
            } catch {
                TextPredictionEngine.writeLog("SwiftLlama init FAILED: \(error)")
                TextPredictionEngine.writeLog("Error type: \(type(of: error)), description: \(error.localizedDescription)")
                throw PredictionError.modelLoadFailed("\(error)")
            }
        }.value

        llama = loadedLlama
        modelPath = path
        isModelLoaded = true
        log("TextPredictionEngine: Model loaded successfully")
    }

    /// Load the default TinyLlama model from Application Support
    func loadDefaultModel() async throws {
        let modelsDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("PUSH/models/text")

        let path = modelsDir.appendingPathComponent(TextModel.tinyLlama.filename).path
        log("TextPredictionEngine: Default model path: \(path)")
        try await loadModel(path: path)
    }

    /// Generate a prediction for the given typing context
    func predictNext(context: String) async -> String {
        guard isModelLoaded, let llama = llama else {
            return ""
        }

        guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        guard !isProcessing else {
            return ""
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Build system prompt with optional personal context
            var systemPrompt = "Continue the user's text naturally. Output ONLY the completion, no explanation."
            if !personalContext.isEmpty {
                systemPrompt = "You are writing as this person: \(personalContext)\n\n\(systemPrompt)"
            }

            // Use chatML format — TinyLlama is trained with ChatML
            let prompt = Prompt(
                type: .chatML,
                systemPrompt: systemPrompt,
                userMessage: context
            )

            let result: String = try await llama.start(for: prompt)

            // Clean up: take only a short completion
            let cleaned = cleanPrediction(result, context: context)
            currentPrediction = cleaned
            return cleaned
        } catch {
            log("TextPredictionEngine: Prediction failed: \(error)")
            return ""
        }
    }

    /// Clear current prediction
    func clearPrediction() {
        currentPrediction = ""
    }

    /// Unload the model to free memory
    func unloadModel() {
        llama = nil
        isModelLoaded = false
        modelPath = nil
        currentPrediction = ""
        log("TextPredictionEngine: Model unloaded")
    }

    // MARK: - Private

    private func cleanPrediction(_ raw: String, context: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the model echoed the context, strip it
        if text.hasPrefix(context) {
            text = String(text.dropFirst(context.count))
        }

        // Take at most ~50 chars or first newline
        if let newlineIndex = text.firstIndex(of: "\n") {
            text = String(text[text.startIndex..<newlineIndex])
        }
        if text.count > 50 {
            // Try to break at a word boundary
            let prefix = String(text.prefix(50))
            if let lastSpace = prefix.lastIndex(of: " ") {
                text = String(prefix[prefix.startIndex..<lastSpace])
            } else {
                text = prefix
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
