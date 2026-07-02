import Foundation
import SwiftLlama

/// On-device LLM gate for the context-aware dictionary (5.1.0 Phase 2).
///
/// Loads a small quantized model (Qwen2.5-0.5B) once, keeps it warm, and judges
/// ambiguous `.contextual` matches with the few-shot prompt validated in the POC
/// (~40 ms warm, well under the 200 ms budget). Fail-safe: if the model isn't
/// bundled, isn't warm, or inference throws, `judge` returns nil so the caller
/// falls back to the heuristic gate.
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
            let config = Configuration(
                topK: 20,
                topP: 0.9,
                nCTX: 2048,
                temperature: 0.0,
                maxTokenCount: 48,
                stopTokens: ["\n\n", "<|im_end|>"]
            )
            let engine = try SwiftLlama(modelPath: url.path, modelConfiguration: config)
            self.llama = engine
            // A dummy judgement compiles Metal shaders so the first real call is fast.
            _ = try? await engine.start(for: Self.prompt(sentence: "warm up", candidates: []))
            isReady = true
            PushLogger.log("LlamaGate: model warm and ready")
        } catch {
            PushLogger.log("LlamaGate: failed to load model — using heuristics")
        }
    }

    private static func prompt(sentence: String, candidates: [CorrectionCandidate]) -> Prompt {
        let history = ContextGatePrompt.fewShot.map { Chat(user: $0.user, bot: $0.assistant) }
        return Prompt(
            type: .chatML,
            systemPrompt: ContextGatePrompt.systemPrompt,
            userMessage: ContextGatePrompt.userMessage(sentence: sentence, candidates: candidates),
            history: history
        )
    }

    /// Judge a batch. Returns verdicts, or nil to tell the caller to fall back.
    func judge(sentence: String, candidates: [CorrectionCandidate]) async -> [CorrectionVerdict]? {
        guard isReady, let llama, !candidates.isEmpty else { return nil }
        do {
            let output = try await llama.start(for: Self.prompt(sentence: sentence, candidates: candidates))
            return ContextGatePrompt.parse(output, count: candidates.count)
        } catch {
            PushLogger.log("LlamaGate: inference error — falling back to heuristics")
            return nil
        }
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
