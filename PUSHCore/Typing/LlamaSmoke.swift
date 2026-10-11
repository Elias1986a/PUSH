import Foundation
import llama

/// Phase 0 proof that llama.cpp loads and generates in-process. Temporary:
/// `LlamaEngine` (Phase 3) replaces it.
public enum LlamaSmoke {
    public enum Failure: Error {
        case modelLoad, context, tokenize, decode
    }

    /// Loads the model, decodes `prompt` greedily for up to `maxTokens` and
    /// returns the continuation. Everything is freed before returning.
    public static func generate(modelPath: String, prompt: String, maxTokens: Int) throws -> String {
        llama_backend_init()
        defer { llama_backend_free() }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = -1  // everything on the GPU
        guard let model = llama_model_load_from_file(modelPath, modelParams) else { throw Failure.modelLoad }
        defer { llama_model_free(model) }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048
        contextParams.n_batch = 2048
        guard let context = llama_init_from_model(model, contextParams) else { throw Failure.context }
        defer { llama_free(context) }

        let vocab = llama_model_get_vocab(model)
        let utf8 = Array(prompt.utf8CString)
        let byteCount = Int32(utf8.count - 1)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 8)
        let n = llama_tokenize(vocab, utf8, byteCount, &tokens, Int32(tokens.count), true, false)
        guard n > 0 else { throw Failure.tokenize }
        tokens.removeLast(tokens.count - Int(n))

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw Failure.context
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        var bytes: [UInt8] = []
        var batch = llama_batch_get_one(&tokens, n)
        guard llama_decode(context, batch) == 0 else { throw Failure.decode }
        for _ in 0..<maxTokens {
            var next = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, next) { break }
            var piece = [CChar](repeating: 0, count: 64)
            let length = llama_token_to_piece(vocab, next, &piece, Int32(piece.count), 0, false)
            if length > 0 { bytes += piece.prefix(Int(length)).map { UInt8(bitPattern: $0) } }
            batch = llama_batch_get_one(&next, 1)
            guard llama_decode(context, batch) == 0 else { throw Failure.decode }
        }
        // Pieces can split a multi-byte character; decode the bytes once at the end.
        return String(decoding: bytes, as: UTF8.self)
    }
}
