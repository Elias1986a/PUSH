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

    /// One loaded model answering `prompts` in turn, reusing the KV cache the
    /// way `llama-server`'s `cache_prompt` does: keep the longest common token
    /// prefix with the previous request, drop the rest, decode the new tail.
    /// Granite 4.0 broke on its third request this way on Metal (Homebrew build
    /// 10566), which a single `generate` call cannot show.
    public static func generateSequence(modelPath: String, prompts: [String], maxTokens: Int) throws -> [String] {
        llama_backend_init()
        defer { llama_backend_free() }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = -1
        guard let model = llama_model_load_from_file(modelPath, modelParams) else { throw Failure.modelLoad }
        defer { llama_model_free(model) }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 4096
        contextParams.n_batch = 2048
        guard let context = llama_init_from_model(model, contextParams) else { throw Failure.context }
        defer { llama_free(context) }

        let vocab = llama_model_get_vocab(model)
        let memory = llama_get_memory(context)
        var cached: [llama_token] = []  // tokens currently in the KV cache
        var outputs: [String] = []

        for prompt in prompts {
            let utf8 = Array(prompt.utf8CString)
            var tokens = [llama_token](repeating: 0, count: utf8.count + 8)
            let n = llama_tokenize(vocab, utf8, Int32(utf8.count - 1), &tokens, Int32(tokens.count), true, false)
            guard n > 0 else { throw Failure.tokenize }
            tokens.removeLast(tokens.count - Int(n))

            // Reuse the shared prefix; always re-decode at least the last token
            // so there are fresh logits to sample from.
            var keep = zip(cached, tokens).prefix { $0 == $1 }.count
            keep = min(keep, tokens.count - 1)
            _ = llama_memory_seq_rm(memory, 0, Int32(keep), -1)
            cached = Array(cached.prefix(keep))
            var tail = Array(tokens[keep...])
            guard llama_decode(context, llama_batch_get_one(&tail, Int32(tail.count))) == 0 else { throw Failure.decode }
            cached += tail

            guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
                throw Failure.context
            }
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
            var bytes: [UInt8] = []
            for _ in 0..<maxTokens {
                var next = llama_sampler_sample(sampler, context, -1)
                if llama_vocab_is_eog(vocab, next) { break }
                var piece = [CChar](repeating: 0, count: 64)
                let length = llama_token_to_piece(vocab, next, &piece, Int32(piece.count), 0, false)
                if length > 0 { bytes += piece.prefix(Int(length)).map { UInt8(bitPattern: $0) } }
                guard llama_decode(context, llama_batch_get_one(&next, 1)) == 0 else {
                    llama_sampler_free(sampler)
                    throw Failure.decode
                }
                cached.append(next)
            }
            llama_sampler_free(sampler)
            outputs.append(String(decoding: bytes, as: UTF8.self))
        }
        return outputs
    }
}
