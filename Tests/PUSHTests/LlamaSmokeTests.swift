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

    /// Many requests on one loaded model with KV-cache reuse — the pattern
    /// that turned Granite 4.0 into "@@@@" on Metal under Homebrew llama.cpp.
    /// Skipped unless `PUSH_LLAMA_REPEAT_MODEL` is set.
    func testRepeatedRequestsWithCacheReuseStayCoherent() throws {
        guard let path = ProcessInfo.processInfo.environment["PUSH_LLAMA_REPEAT_MODEL"] else {
            throw XCTSkip("PUSH_LLAMA_REPEAT_MODEL not set")
        }
        let surface = "Format: chat; App: Slack; Title: #design; Field: Message #design.\n\n"
        var prompts = [
            // The exact sequence that broke under Homebrew build 10566.
            "The capital of France is",
            "Warm up the graph with",
            surface + "Hey, can you send me the latest mock",
            "Hey, can you send me the latest mock",
            "The capital of France is",
        ]
        prompts += [
            "Hi Priya,\n\nThanks for sending this over. I had a quick look and overall it looks",
            "Running a bit late, I'll be there in",
            "Eggs, milk, bread, butter,",
            "Let me know if you have any",
            "I hope this email finds you",
            "Steps to reproduce:\n1. Open the app\n2. Tap on a title\n3. Press play\n\nActual behavior: the",
        ]
        // Keystrokes: each request extends the previous one by a character.
        var draft = surface + "Quick update: the new season drops on Friday, so we need the"
        for ch in " artwork by" {
            draft.append(ch)
            prompts.append(draft)
        }
        let outputs = try LlamaSmoke.generateSequence(modelPath: (path as NSString).expandingTildeInPath,
                                                      prompts: prompts, maxTokens: 10)
        for (i, out) in outputs.enumerated() {
            print("repeat \(i): \(out.debugDescription)")
            XCTAssertFalse(Self.isGarbage(out), "request \(i) degenerated: \(out.debugDescription)")
        }
        XCTAssertTrue(outputs[0].contains("Paris"))
        XCTAssertTrue(outputs[4].contains("Paris"), "the fifth request repeats the first; it must still say Paris")
    }

    /// "@@@@" and its kin: one non-letter character repeated, or no letters at all.
    static func isGarbage(_ text: String) -> Bool {
        let chars = Array(text)
        if chars.count >= 4, !chars.contains(where: \.isLetter) { return true }
        var run = 1
        for i in chars.indices.dropFirst() {
            run = (chars[i] == chars[i - 1] && !chars[i].isLetter) ? run + 1 : 1
            if run >= 4 && chars[i] != " " && chars[i] != "." { return true }
        }
        return false
    }
}
