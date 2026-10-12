import XCTest
@testable import PUSHCore

/// Pure parts always run. Model tests run when `PUSH_TYPE_MODELS_DIR` points at
/// a folder holding the catalog's GGUF files, each model that is present.
final class LlamaEngineTests: XCTestCase {

    // MARK: - Pure

    func testSplitValidUTF8HoldsBackASplitCharacter() {
        let wave = Array("👋".utf8)                                   // 4 bytes
        let (text, rest) = LlamaEngine.splitValidUTF8(Data(Array("hi ".utf8) + wave.prefix(2)))
        XCTAssertEqual(text, "hi ")
        XCTAssertEqual(Array(rest), Array(wave.prefix(2)))
        XCTAssertEqual(LlamaEngine.splitValidUTF8(Data(rest + wave.suffix(2))).0, "👋")
    }

    func testSplitValidUTF8PassesCompleteText() {
        XCTAssertEqual(LlamaEngine.splitValidUTF8(Data("wörld 🎬".utf8)).0, "wörld 🎬")
        XCTAssertEqual(LlamaEngine.splitValidUTF8(Data()).0, "")
    }

    func testCommonPrefix() {
        XCTAssertEqual(LlamaEngine.commonPrefix([1, 2, 3], [1, 2, 4, 5]), 2)
        XCTAssertEqual(LlamaEngine.commonPrefix([], [1]), 0)
    }

    // MARK: - With models

    private func models() throws -> [(TypingModel, String)] {
        guard let dir = ProcessInfo.processInfo.environment["PUSH_TYPE_MODELS_DIR"] else {
            throw XCTSkip("PUSH_TYPE_MODELS_DIR not set")
        }
        let found = TypingModel.allCases.compactMap { model -> (TypingModel, String)? in
            let path = ((dir as NSString).expandingTildeInPath as NSString).appendingPathComponent(model.file)
            return FileManager.default.fileExists(atPath: path) ? (model, path) : nil
        }
        if found.isEmpty { throw XCTSkip("no catalog model in \(dir)") }
        return found
    }

    private func collect(_ engine: LlamaEngine, _ prompt: String, _ maxTokens: Int = 12,
                         forcing: String = "", wordBoundary: Bool = false) async throws -> String {
        var out = ""
        for try await piece in await engine.complete(prompt: prompt, maxTokens: maxTokens,
                                                     forcing: forcing, wordBoundary: wordBoundary) { out += piece }
        return out
    }

    func testGeneratesAContinuation() async throws {
        for (model, path) in try models() {
            let engine = LlamaEngine()
            try await engine.load(path: path)
            let out = try await collect(engine, "Capitals: Italy, Rome. Spain, Madrid. France,", 8)
            XCTAssertTrue(out.contains("Paris"), "\(model): \(out.debugDescription)")
            await engine.unload()
        }
    }

    /// The test that matters: an answer built on reused work must equal the
    /// answer built from scratch. Qwen3.5 is hybrid and cannot trim its cache;
    /// reusing it naively gives fluent but wrong text.
    func testReusedAnswersEqualColdAnswers() async throws {
        let surface = "Format: chat; App: Slack; Title: #design; Field: Message #design.\n\n"
        var prompts = ["The capital of France is", surface + "Hey, can you send me the latest"]
        var draft = surface + "Quick update: the new season drops on Friday, so we need the"
        for word in [" artwork", " by", " Wednesday", " at", " the"] {
            draft += word
            prompts.append(draft)
        }
        prompts.append(draft)                      // the same prompt again (typing inside a word)
        prompts.append("Hi Priya,\n\nThanks for sending this over. Overall it looks")
        for (model, path) in try models() {
            let engine = LlamaEngine()
            try await engine.load(path: path)
            for (i, prompt) in prompts.enumerated() {
                let reused = try await collect(engine, prompt)
                await engine.resetCache()
                let cold = try await collect(engine, prompt)
                XCTAssertEqual(reused, cold, "\(model) request \(i)")
            }
            await engine.unload()
        }
    }

    func testExtendingThePromptDecodesOnlyTheNewTokens() async throws {
        for (model, path) in try models() {
            let engine = LlamaEngine()
            try await engine.load(path: path)
            let base = String(repeating: "We shipped the downloads feature two weeks early. ", count: 30)
            _ = try await collect(engine, base + "Next we", 4)
            let cold = await engine.lastStats
            _ = try await collect(engine, base + "Next we will", 4)
            let warm = await engine.lastStats
            XCTAssertGreaterThan(cold.decodedPromptTokens, 200, "\(model)")
            XCTAssertLessThanOrEqual(warm.decodedPromptTokens, 4, "\(model)")
            print("reuse \(model.rawValue): cold \(cold.decodedPromptTokens) tok, first token \(Int(cold.firstTokenMilliseconds)) ms → warm \(warm.decodedPromptTokens) tok, first token \(Int(warm.firstTokenMilliseconds)) ms")
            await engine.unload()
        }
    }

    func testGrammarForcesTheStart() async throws {
        for (model, path) in try models() {
            let engine = LlamaEngine()
            try await engine.load(path: path)
            let heal = TokenHealing.split("Thanks for jumping on that so fast, really appreci")
            let out = try await collect(engine, heal.prompt, 8, forcing: heal.forced)
            XCTAssertTrue(out.hasPrefix(" appreci"), "\(model): \(out.debugDescription)")
            await engine.unload()
        }
    }

    /// Every grammar the app builds must parse in llama.cpp itself — an
    /// escaped hyphen once made the word-break retry fail silently. These
    /// starts are unlikely after "Note:", so the grammar fallback runs.
    func testTheAppsGrammarsParse() async throws {
        let (model, path) = try models()[0]
        let engine = LlamaEngine()
        try await engine.load(path: path)
        for (forced, boundary) in [(" appreci", false), ("Hello", true), (#"say "hi\"#, true)] {
            let out = try await collect(engine, "Note:\n\n", 16, forcing: forced, wordBoundary: boundary)
            XCTAssertTrue(out.hasPrefix(forced), "\(model) \(forced): \(out.debugDescription)")
            if boundary, let next = out.dropFirst(forced.count).first {
                XCTAssertTrue(" ,.!?;:'\")’".contains(next), "\(model) \(forced): \(out.debugDescription)")
            }
        }
        await engine.unload()
    }

    /// Prints the confidence of short cold-start completions — the data the
    /// near-empty-page gate's floor is set from.
    func testColdStartConfidence() async throws {
        let starts = ["Hello", "Hi", "hey", "Good morning", "Thanks", "So", "Quick question", "I wanted",
                      "Hello,", "Can you"]
        for (model, path) in try models() {
            let engine = LlamaEngine()
            try await engine.load(path: path)
            await engine.setRecordsLogprobs(true)
            for start in starts {
                let heal = TokenHealing.split(start)
                let out = try await collect(engine, "Format: text; App: Notes.\n\n" + heal.prompt, 8,
                                            forcing: heal.forced, wordBoundary: true)
                let lp = await engine.lastStats.tokenLogprobs
                let forcedTokens = heal.forced.isEmpty ? 0 : 1
                let gen = Array(lp.dropFirst(forcedTokens))
                let mean = gen.isEmpty ? 0 : gen.reduce(0, +) / Double(gen.count)
                print("conf \(model.rawValue) \(start.debugDescription) -> \(String(out.dropFirst(heal.forced.count)).debugDescription) mean \(String(format: "%.2f", mean)) first3 \(gen.prefix(3).map { String(format: "%.1f", $0) })")
            }
            await engine.unload()
        }
    }

    func testCancellingStopsAndTheNextRequestWorks() async throws {
        for (model, path) in try models() {
            let engine = LlamaEngine()
            try await engine.load(path: path)
            let consumer = Task {
                var pieces = 0
                for try await _ in await engine.complete(prompt: "Once upon a time", maxTokens: 400) {
                    pieces += 1
                    if pieces == 2 { break }
                }
                return pieces
            }
            let pieces = try await consumer.value
            XCTAssertEqual(pieces, 2, "\(model)")
            let out = try await collect(engine, "Capitals: Italy, Rome. Spain, Madrid. France,", 8)
            XCTAssertTrue(out.contains("Paris"), "\(model) after cancel: \(out.debugDescription)")
            await engine.unload()
        }
    }
}
