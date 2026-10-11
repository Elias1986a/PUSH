import XCTest
@testable import PUSHCore

/// Temporary (Phase 0): llama.cpp loads a GGUF and generates. Skipped unless
/// `PUSH_LLAMA_SMOKE_MODEL` points at a model file.
final class LlamaSmokeTests: XCTestCase {
    func testGeneratesAContinuation() throws {
        guard let path = ProcessInfo.processInfo.environment["PUSH_LLAMA_SMOKE_MODEL"] else {
            throw XCTSkip("PUSH_LLAMA_SMOKE_MODEL not set")
        }
        let start = Date()
        let text = try LlamaSmoke.generate(modelPath: (path as NSString).expandingTildeInPath,
                                           prompt: "The capital of France is", maxTokens: 8)
        print("llama smoke: \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        XCTAssertTrue(text.contains("Paris"), "got \(text.debugDescription)")
    }
}
