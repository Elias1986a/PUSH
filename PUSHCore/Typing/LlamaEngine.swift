import Foundation
import llama

/// Type's text engine: one GGUF model in-process on the GPU, continuing
/// prompts token by token.
///
/// Keystroke to keystroke the prompt barely changes, so the work already done
/// on it is reused. Attention-only models (Gemma) trim their KV cache back to
/// the shared prefix. Hybrid models (Qwen3.5: attention plus recurrent layers)
/// cannot trim — `llama_memory_seq_rm` refuses a partial removal — so for them
/// the engine snapshots the sequence state at the end of each prompt (less its
/// last token) and restores it when the next prompt extends it.
public actor LlamaEngine {
    public static let shared = LlamaEngine()

    public enum Failure: Error, Equatable {
        case notLoaded, modelLoad, context, tokenize, decode, grammar
    }

    /// What the last request cost, for tests and operational logs (never text).
    public struct Stats: Sendable, Equatable {
        public var promptTokens = 0
        public var decodedPromptTokens = 0
        /// From the request to the first sampled token, prompt work included
        /// (the GPU finishes lazily, so timing the decode alone undercounts).
        public var firstTokenMilliseconds = 0.0
        /// Natural-log probability of each generated token, in order — how
        /// sure the model was. Callers gate low-confidence guesses on it.
        public var tokenLogprobs: [Double] = []
    }

    /// How the next token is chosen: greedy, behind a mild repetition penalty
    /// over the recent text (Cotabby's 1.025 over the last 64 tokens) — pure
    /// greedy decoding fell into "3 3 3 3". Cotabby also samples at
    /// temperature 0.1 with top-k/top-p/min-p; measured here that flipped
    /// "Paris" to "a city that…", broke reused-equals-cold, and doubled the
    /// per-keystroke time (Gemma 34 → 69 ms), so only the penalty is taken.
    public struct Sampling: Sendable, Equatable {
        public var repetitionPenalty: Float = 1.025
        public var penaltyLastN: Int32 = 64

        public init() {}
        public static let standard = Sampling()
    }

    public private(set) var lastStats = Stats()
    /// Record per-token log-probabilities in `lastStats` (a pass over the
    /// whole vocabulary per token — diagnostics only, off in the app).
    public var recordsLogprobs = false
    public func setRecordsLogprobs(_ on: Bool) { recordsLogprobs = on }
    public private(set) var loadedPath: String?

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var canTrim = true
    private var batchSize: Int32 = 512

    /// Tokens whose effect is in the context right now (prompt plus generated).
    private var cached: [llama_token] = []
    /// Hybrid models: the state after `snapshotTokens`, and those tokens.
    private var snapshot: [UInt8] = []
    private var snapshotTokens: [llama_token] = []

    public init() {}

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    private static let backend: Void = { llama_backend_init() }()

    // MARK: - Lifecycle

    public func load(path: String, contextSize: Int32 = 4096) throws {
        unload()
        _ = Self.backend
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = -1
        guard let model = llama_model_load_from_file(path, modelParams) else { throw Failure.modelLoad }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = UInt32(batchSize)
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw Failure.context
        }
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.canTrim = !(llama_model_is_hybrid(model) || llama_model_is_recurrent(model))
        self.loadedPath = path
    }

    public func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        vocab = nil
        loadedPath = nil
        cached = []
        snapshot = []
        snapshotTokens = []
    }

    public var isLoaded: Bool { context != nil }

    /// Forgets everything reused between requests, so the next one starts
    /// cold. Tests compare reused answers against cold ones with it.
    func resetCache() {
        if let context { llama_memory_clear(llama_get_memory(context), true) }
        cached = []
        snapshot = []
        snapshotTokens = []
    }

    // MARK: - Completion

    /// Streams the continuation of `prompt` in UTF-8-safe pieces. Stops at a
    /// newline (not included), an end-of-generation token or `maxTokens`.
    /// The output starts with `forcing` (token healing's partial word), then
    /// a space or punctuation when `wordBoundary`. Cancelling the consuming
    /// task stops generation within a token. `parseSpecial` reads control
    /// tags in the prompt (a chat template's `<|im_start|>`) as the special
    /// tokens they name instead of as text; Type's plain prompts leave it off.
    public func complete(prompt: String, maxTokens: Int, forcing: String = "", wordBoundary: Bool = false,
                         sampling: Sampling = .standard,
                         parseSpecial: Bool = false) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.run(prompt: prompt, maxTokens: maxTokens,
                               forced: ForcedStart(forcing, wordBoundary: wordBoundary),
                               sampling: sampling, parseSpecial: parseSpecial, into: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(prompt: String, maxTokens: Int, forced: ForcedStart, sampling: Sampling, parseSpecial: Bool,
                     into continuation: AsyncThrowingStream<String, Error>.Continuation) {
        do {
            try generate(prompt: prompt, maxTokens: maxTokens, forced: forced, sampling: sampling,
                         parseSpecial: parseSpecial) { continuation.yield($0) }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func generate(prompt: String, maxTokens: Int, forced: ForcedStart, sampling: Sampling,
                          parseSpecial: Bool = false, emit: (String) -> Void) throws {
        guard let context, let vocab else { throw Failure.notLoaded }
        let tokens = try tokenize(prompt, parseSpecial: parseSpecial)
        let start = DispatchTime.now()
        let decoded = try prepare(tokens)
        lastStats = Stats(promptTokens: tokens.count, decodedPromptTokens: decoded)

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw Failure.context }
        defer { llama_sampler_free(sampler) }
        if let penalties = llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), sampling.penaltyLastN,
                                                        sampling.repetitionPenalty, 0, 0) {
            // The penalty sees the user's recent text, not only the model's own output.
            for token in tokens.suffix(Int(sampling.penaltyLastN)) { llama_sampler_accept(penalties, token) }
            llama_sampler_chain_add(sampler, penalties)
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        var forced = forced
        var pending = Data()
        for step in 0..<maxTokens {
            if Task.isCancelled { return }
            let next = try choose(sampler, forced: &forced)
            if recordsLogprobs { lastStats.tokenLogprobs.append(logprob(of: next)) }
            if step == 0 {
                lastStats.firstTokenMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
            }
            if llama_vocab_is_eog(vocab, next) { break }
            pending.append(piece(next))
            guard try decode([next]) else { throw Failure.decode }
            cached.append(next)
            if let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let (text, _) = Self.splitValidUTF8(pending[pending.startIndex..<newline])
                if !text.isEmpty { emit(text) }
                return
            }
            let (text, rest) = Self.splitValidUTF8(pending)
            if !text.isEmpty { emit(text) }
            pending = rest
        }
        let (text, _) = Self.splitValidUTF8(pending)
        if !text.isEmpty { emit(text) }
    }

    /// The next token from `sampler` (greedy behind the repetition penalty).
    /// While a forced start is pending, the model's own choice is tried on a
    /// copy of the sampler — a rejected token must not enter the penalty's
    /// history — and kept when it fits; only otherwise is a grammar for the
    /// rest of the forced text applied.
    private func choose(_ sampler: UnsafeMutablePointer<llama_sampler>, forced: inout ForcedStart) throws -> llama_token {
        guard let context, let vocab else { throw Failure.notLoaded }
        if forced.isDone { return llama_sampler_sample(sampler, context, -1) }
        guard let trial = llama_sampler_clone(sampler) else { throw Failure.context }
        var next = llama_sampler_sample(trial, context, -1)
        llama_sampler_free(trial)
        if !forced.fits(Array(piece(next))) {
            if let grammar = forced.grammar {
                guard let constrained = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw Failure.context }
                defer { llama_sampler_free(constrained) }
                guard let constraint = llama_sampler_init_grammar(vocab, grammar, "root") else { throw Failure.grammar }
                llama_sampler_chain_add(constrained, constraint)
                if let rest = llama_sampler_clone(sampler) { llama_sampler_chain_add(constrained, rest) }
                next = llama_sampler_sample(constrained, context, -1)
            } else {
                forced = ForcedStart("")      // a token split a character: stop enforcing
            }
        }
        llama_sampler_accept(sampler, next)
        forced.advance(by: Array(piece(next)))
        return next
    }

    /// Brings the context to `tokens` minus nothing — fresh logits for the
    /// last token — reusing what it can. Returns how many tokens were decoded.
    private func prepare(_ tokens: [llama_token]) throws -> Int {
        guard let context else { throw Failure.notLoaded }
        let memory = llama_get_memory(context)

        if canTrim {
            // Keep the shared prefix, always re-decoding at least the last token.
            let keep = min(Self.commonPrefix(cached, tokens), tokens.count - 1)
            if !llama_memory_seq_rm(memory, 0, Int32(keep), -1) {
                llama_memory_clear(memory, true)
                cached = []
                return try decodeFresh(tokens)
            }
            cached = Array(cached.prefix(keep))
            let tail = Array(tokens[keep...])
            guard try decode(tail) else { throw Failure.decode }
            cached += tail
            return tail.count
        }

        // Hybrid: restore the snapshot if this prompt extends it, else start over.
        let body = Array(tokens.dropLast())
        var decoded = 0
        if !snapshot.isEmpty, body.count >= snapshotTokens.count,
           Array(body.prefix(snapshotTokens.count)) == snapshotTokens,
           restoreSnapshot() {
            cached = snapshotTokens
            let extra = Array(body[snapshotTokens.count...])
            if !extra.isEmpty {
                guard try decode(extra) else { throw Failure.decode }
                cached += extra
                decoded += extra.count
            }
        } else {
            llama_memory_clear(memory, true)
            cached = []
            if !body.isEmpty {
                guard try decode(body) else { throw Failure.decode }
                cached = body
                decoded += body.count
            }
        }
        if cached != snapshotTokens { takeSnapshot() }
        guard let last = tokens.last, try decode([last]) else { throw Failure.decode }
        cached.append(last)
        return decoded + 1
    }

    private func decodeFresh(_ tokens: [llama_token]) throws -> Int {
        guard try decode(tokens) else { throw Failure.decode }
        cached = tokens
        return tokens.count
    }

    /// Decodes in batches of `batchSize`; logits are left for the last token.
    private func decode(_ tokens: [llama_token]) throws -> Bool {
        guard let context else { throw Failure.notLoaded }
        var offset = 0
        while offset < tokens.count {
            var chunk = Array(tokens[offset..<min(offset + Int(batchSize), tokens.count)])
            let status = chunk.withUnsafeMutableBufferPointer {
                llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count)))
            }
            guard status == 0 else { return false }
            offset += chunk.count
        }
        return true
    }

    private func takeSnapshot() {
        guard let context else { return }
        let size = llama_state_seq_get_size(context, 0)
        var buffer = [UInt8](repeating: 0, count: size)
        let written = buffer.withUnsafeMutableBufferPointer { llama_state_seq_get_data(context, $0.baseAddress, size, 0) }
        snapshot = written == size ? buffer : []
        snapshotTokens = written == size ? cached : []
    }

    private func restoreSnapshot() -> Bool {
        guard let context else { return false }
        llama_memory_clear(llama_get_memory(context), true)
        let read = snapshot.withUnsafeBufferPointer { llama_state_seq_set_data(context, $0.baseAddress, $0.count, 0) }
        return read == snapshot.count
    }

    /// log softmax of the last logits at `token`, over the whole vocabulary
    /// (before the grammar narrowed it): the model's own confidence.
    private func logprob(of token: llama_token) -> Double {
        guard let context, let vocab, let logits = llama_get_logits_ith(context, -1) else { return 0 }
        let n = Int(llama_vocab_n_tokens(vocab))
        var maxLogit = -Float.infinity
        for i in 0..<n where logits[i] > maxLogit { maxLogit = logits[i] }
        var sum = 0.0
        for i in 0..<n { sum += exp(Double(logits[i] - maxLogit)) }
        return Double(logits[Int(token)] - maxLogit) - log(sum)
    }

    // MARK: - Tokens and text

    private func tokenize(_ text: String, parseSpecial: Bool = false) throws -> [llama_token] {
        guard let vocab else { throw Failure.notLoaded }
        let utf8 = Array(text.utf8CString)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 8)
        let n = llama_tokenize(vocab, utf8, Int32(utf8.count - 1), &tokens, Int32(tokens.count), true, parseSpecial)
        guard n > 0 else { throw Failure.tokenize }
        return Array(tokens.prefix(Int(n)))
    }

    private func piece(_ token: llama_token) -> Data {
        guard let vocab else { return Data() }
        var buffer = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return Data(buffer.prefix(max(0, Int(n))).map { UInt8(bitPattern: $0) })
    }

    static func commonPrefix(_ a: [llama_token], _ b: [llama_token]) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }

    /// The longest prefix of `bytes` that is complete UTF-8, decoded, and the
    /// bytes after it (a character a token split in two, held for the next).
    static func splitValidUTF8(_ bytes: Data) -> (String, Data) {
        let all = Array(bytes)
        guard !all.isEmpty else { return ("", Data()) }
        var cut = all.count
        // An incomplete sequence can only be the last 1–3 bytes.
        for back in 1...min(3, all.count) {
            let byte = all[all.count - back]
            if byte & 0b1100_0000 == 0b1000_0000 { continue }        // continuation byte
            let length = byte >= 0b1111_0000 ? 4 : byte >= 0b1110_0000 ? 3 : byte >= 0b1100_0000 ? 2 : 1
            if length > back { cut = all.count - back }
            break
        }
        return (String(decoding: all[..<cut], as: UTF8.self), Data(all[cut...]))
    }
}
