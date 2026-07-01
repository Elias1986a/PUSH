import Foundation
import SwiftLlama

/// On-device LLM gate for the context-aware dictionary (5.1.0 Phase 2).
///
/// Loads a small quantized model (Qwen2.5-0.5B), keeps it warm, and judges
/// ambiguous `.contextual` matches with the few-shot prompt validated in the POC
/// (~110 ms warm on CPU, under the 200 ms budget; 10/12 on the test matrix).
/// Fail-safe: if the model isn't bundled, isn't warm, or inference throws,
/// `judge` returns nil so the caller falls back to the heuristic gate.
///
/// Uses the vendored/patched SwiftLlama (Vendor/SwiftLlama): the prompt is built
/// with the model's own chat template via `formatChat` and fed through the `.raw`
/// prompt type — the stock ChatML encoder drops the system prompt.
actor LlamaGateEngine {
    static let shared = LlamaGateEngine()

    private var llama: SwiftLlama?
    private(set) var isReady = false

    private init() {}

    /// The bundled GGUF. Uses `Bundle.main` (not `Bundle.module`, which crashes in
    /// distribution builds — see project memory).
    private static var modelURL: URL? {
        Bundle.main.url(forResource: "Qwen2.5-0.5B-Instruct-Q4_K_M", withExtension: "gguf")
    }

    /// Load + warm the model. Non-blocking to call; safe to invoke once at launch.
    func warmup() async {
        guard llama == nil else { return }
        guard let url = Self.modelURL else {
            PushLogger.log("LlamaGate: model not bundled — contextual gate falls back to heuristics")
            return
        }
        do {
            // temperature 0 → greedy (deterministic), matching the validated POC.
            let config = Configuration(
                topK: 5,
                topP: 0.9,
                nCTX: 2048,
                temperature: 0.0,
                maxTokenCount: 24,
                stopTokens: ["<|im_end|>"]
            )
            let engine = try SwiftLlama(modelPath: url.path, modelConfiguration: config)
            self.llama = engine
            // A dummy judgement warms the pipeline so the first real call is fast.
            _ = await Self.run(engine, sentence: "warm up", candidates: [
                CorrectionCandidate(matchedText: "x", location: 0, replacement: "x", entity: nil)
            ])
            isReady = true
            PushLogger.log("LlamaGate: model warm and ready")
        } catch {
            PushLogger.log("LlamaGate: failed to load model — using heuristics")
        }
    }

    /// Build the prompt with the model's own template + run it. Returns nil on any error.
    private static func run(_ llama: SwiftLlama, sentence: String, candidates: [CorrectionCandidate]) async -> [CorrectionVerdict]? {
        var messages: [(role: String, content: String)] = [("system", ContextGatePrompt.systemPrompt)]
        for ex in ContextGatePrompt.fewShot {
            messages.append(("user", ex.user))
            messages.append(("assistant", ex.assistant))
        }
        messages.append(("user", ContextGatePrompt.userMessage(sentence: sentence, candidates: candidates)))
        do {
            let prompt = await llama.formatChat(messages, addAssistant: true)
            let output = try await llama.start(for: Prompt(type: .raw, userMessage: prompt))
            return ContextGatePrompt.parse(output, count: candidates.count)
        } catch {
            return nil
        }
    }

    /// Judge a batch. Returns verdicts, or nil to tell the caller to fall back.
    func judge(sentence: String, candidates: [CorrectionCandidate]) async -> [CorrectionVerdict]? {
        guard isReady, let llama, !candidates.isEmpty else { return nil }
        if let verdicts = await Self.run(llama, sentence: sentence, candidates: candidates) {
            return verdicts
        }
        PushLogger.log("LlamaGate: inference error — falling back to heuristics")
        return nil
    }
}

/// The shipping verdict source: prefer the warm on-device model, fall back to the
/// zero-latency heuristics whenever the model can't answer. Both are fail-safe.
struct GateVerdictSource: VerdictSource {
    func judge(sentence: String, candidates: [CorrectionCandidate]) async -> [CorrectionVerdict] {
        if let verdicts = await LlamaGateEngine.shared.judge(sentence: sentence, candidates: candidates) {
            return verdicts
        }
        return await HeuristicVerdictSource().judge(sentence: sentence, candidates: candidates)
    }
}
