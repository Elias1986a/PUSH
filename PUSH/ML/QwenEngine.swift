import Foundation
import llama

/// Wrapper for llama.cpp to run Qwen text formatting
actor QwenEngine {
    static let shared = QwenEngine()

    private var model: OpaquePointer?
    private var context: OpaquePointer?
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

        let modelPath = ModelManager.shared.modelPath(for: model.rawValue + ".gguf")

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw QwenError.modelNotFound(model.rawValue)
        }

        print("QwenEngine: Loading model from \(modelPath.path)")

        // Initialize llama.cpp
        llama_backend_init()

        // Model parameters
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99  // Use GPU acceleration

        // Load model
        guard let loadedModel = llama_load_model_from_file(modelPath.path, modelParams) else {
            throw QwenError.loadFailed("Failed to load model")
        }

        self.model = loadedModel

        // Context parameters
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 2048
        ctxParams.n_threads = UInt32(ProcessInfo.processInfo.processorCount)
        ctxParams.n_threads_batch = UInt32(ProcessInfo.processInfo.processorCount)

        // Create context
        guard let ctx = llama_new_context_with_model(loadedModel, ctxParams) else {
            llama_free_model(loadedModel)
            throw QwenError.loadFailed("Failed to create context")
        }

        self.context = ctx
        isLoaded = true
        print("QwenEngine: Model loaded successfully")
    }

    /// Unload the current model
    func unloadModel() {
        if let ctx = context {
            llama_free(ctx)
        }
        if let m = model {
            llama_free_model(m)
        }
        context = nil
        model = nil
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

        guard let ctx = context, let mdl = model else {
            throw QwenError.notInitialized
        }

        // Build the prompt using Qwen chat format
        let prompt = buildPrompt(text)

        print("QwenEngine: Formatting text...")

        // Tokenize
        let tokens = tokenize(ctx: ctx, text: prompt, addBos: true)

        guard !tokens.isEmpty else {
            throw QwenError.tokenizationFailed
        }

        // Generate
        let output = try generate(ctx: ctx, model: mdl, tokens: tokens, maxTokens: 256)

        let formatted = cleanOutput(output)
        print("QwenEngine: Formatting complete")

        return formatted
    }

    // MARK: - Private

    private func buildPrompt(_ text: String) -> String {
        // Qwen 3 chat format
        return """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        \(text)<|im_end|>
        <|im_start|>assistant
        """
    }

    private func tokenize(ctx: OpaquePointer, text: String, addBos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: utf8Count + 1)

        let n = llama_tokenize(
            llama_get_model(ctx),
            text,
            Int32(utf8Count),
            &tokens,
            Int32(tokens.count),
            addBos,
            false  // special tokens
        )

        if n < 0 {
            return []
        }

        return Array(tokens.prefix(Int(n)))
    }

    private func generate(ctx: OpaquePointer, model: OpaquePointer, tokens: [llama_token], maxTokens: Int) throws -> String {
        var outputTokens = [llama_token]()
        var inputTokens = tokens

        // Create batch
        var batch = llama_batch_init(Int32(tokens.count + maxTokens), 0, 1)
        defer { llama_batch_free(batch) }

        // Add input tokens to batch
        for (i, token) in inputTokens.enumerated() {
            llama_batch_add(&batch, token, Int32(i), [0], i == inputTokens.count - 1)
        }

        // Evaluate input
        if llama_decode(ctx, batch) != 0 {
            throw QwenError.decodeFailed
        }

        var nCur = inputTokens.count

        // Generate tokens
        for _ in 0..<maxTokens {
            // Sample next token
            let logits = llama_get_logits_ith(ctx, Int32(batch.n_tokens - 1))
            let nVocab = llama_n_vocab(model)

            var candidates = [llama_token_data]()
            for tokenId in 0..<nVocab {
                candidates.append(llama_token_data(id: tokenId, logit: logits![Int(tokenId)], p: 0))
            }

            var candidatesP = llama_token_data_array(
                data: &candidates,
                size: candidates.count,
                selected: -1,
                sorted: false
            )

            // Greedy sampling (fastest)
            let newToken = llama_sample_token_greedy(ctx, &candidatesP)

            // Check for end of sequence
            if llama_token_is_eog(model, newToken) {
                break
            }

            outputTokens.append(newToken)

            // Prepare next batch
            llama_batch_clear(&batch)
            llama_batch_add(&batch, newToken, Int32(nCur), [0], true)
            nCur += 1

            if llama_decode(ctx, batch) != 0 {
                throw QwenError.decodeFailed
            }
        }

        // Detokenize
        return detokenize(model: model, tokens: outputTokens)
    }

    private func detokenize(model: OpaquePointer, tokens: [llama_token]) -> String {
        var output = ""

        for token in tokens {
            var buffer = [CChar](repeating: 0, count: 256)
            let n = llama_token_to_piece(model, token, &buffer, Int32(buffer.count), 0, false)
            if n > 0 {
                buffer[Int(n)] = 0
                if let str = String(cString: buffer, encoding: .utf8) {
                    output += str
                }
            }
        }

        return output
    }

    private func cleanOutput(_ text: String) -> String {
        // Remove any special tokens that might have leaked through
        var cleaned = text
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|im_start|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
}

// MARK: - Errors

enum QwenError: LocalizedError {
    case modelNotFound(String)
    case notInitialized
    case loadFailed(String)
    case tokenizationFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let model):
            return "Qwen model not found: \(model). Please download it in Settings."
        case .notInitialized:
            return "Qwen engine not initialized"
        case .loadFailed(let reason):
            return "Failed to load Qwen: \(reason)"
        case .tokenizationFailed:
            return "Failed to tokenize input"
        case .decodeFailed:
            return "Failed to decode tokens"
        }
    }
}

// MARK: - llama.cpp batch helpers

extension llama_batch {
    mutating func clear() {
        self.n_tokens = 0
    }
}

func llama_batch_add(_ batch: inout llama_batch, _ token: llama_token, _ pos: Int32, _ seqIds: [Int32], _ logits: Bool) {
    let i = Int(batch.n_tokens)

    batch.token[i] = token
    batch.pos[i] = pos
    batch.n_seq_id[i] = Int32(seqIds.count)

    for (j, seqId) in seqIds.enumerated() {
        batch.seq_id[i]![j] = seqId
    }

    batch.logits[i] = logits ? 1 : 0

    batch.n_tokens += 1
}
