import AppKit
import XCTest
@testable import PUSH
import PUSHCore

/// The replay eval: every scenario through the app's own pipeline — gate,
/// token healing, prompt, engine, `SuggestionJudge` — at three caret
/// positions: right after a word, after the space, and two letters into the
/// next word. The Phase 0 eval called the model directly and missed the
/// trailing-space bug; this one runs what users see.
///
///     PUSH_TYPE_EVAL=1 PUSH_TYPE_MODELS_DIR=~/Library/Application\ Support/PUSH/TypingModels \
///       swift test --filter TypingReplayEvalTests
///
/// Optional: PUSH_TYPE_EVAL_MODELS=gemma4-e2b-base,qwen3.5-2b-base. Writes
/// eval/results/replay-latest.md.
@MainActor
final class TypingReplayEvalTests: XCTestCase {
    struct Scenario: Decodable {
        let id: String
        let surface: String
        let before: String
        let expected: String
        let midword: Bool?
    }

    enum Variant: String, CaseIterable { case word, space, mid }

    struct Checkpoint {
        let scenario: String
        let variant: Variant
        let before: String
        /// The word the user goes on to write at the caret.
        let target: String
        /// Letters of it already typed (mid-word).
        let typed: String
    }

    struct Result {
        let checkpoint: Checkpoint
        let shown: String?
        let reason: String?
        let ms: Double
        var hit: Bool {
            guard let shown else { return false }
            let lead = checkpoint.typed.isEmpty ? shown.drop { $0 == " " } : Substring(shown)
            let completed = checkpoint.typed + lead.prefix { $0.isLetter || $0 == "'" || $0 == "’" }
            return Self.norm(String(completed)) == Self.norm(checkpoint.target)
        }
        /// Digits or markup the text never had: the junk end of the model.
        var junk: Bool {
            guard let shown else { return false }
            return shown.contains { $0.isNumber || $0 == "<" || $0 == ">" } && !checkpoint.before.contains { $0.isNumber }
        }
        static func norm(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter }
        }
    }

    // MARK: - Checkpoints

    static func checkpoints(_ s: Scenario) -> [Checkpoint] {
        let firstWord = { (text: String) in String(text.drop { $0 == " " }.prefix { !$0.isWhitespace && !",.!?;:".contains($0) }) }
        if s.midword == true {
            let partial = String(s.before.reversed().prefix { $0.isLetter || $0 == "'" }.reversed())
            return [Checkpoint(scenario: s.id, variant: .mid, before: s.before,
                               target: partial + firstWord(s.expected), typed: partial)]
        }
        let target = firstWord(s.expected)
        guard !target.isEmpty else { return [] }
        var result = [Checkpoint(scenario: s.id, variant: .word, before: s.before, target: target, typed: "")]
        // Nobody types a space at the start of an empty line ("Thanks,⏎ ").
        let atLineStart = s.before.last?.isNewline == true
        if !atLineStart {
            result.append(Checkpoint(scenario: s.id, variant: .space, before: s.before + " ", target: target, typed: ""))
        }
        if target.count >= 4, !atLineStart {
            let typed = String(target.prefix(2))
            result.append(Checkpoint(scenario: s.id, variant: .mid, before: s.before + " " + typed,
                                     target: target, typed: typed))
        }
        return result
    }

    // MARK: - The app's pipeline

    private static func isRealWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }

    /// One suggestion, as `TypingCoordinator.suggest` would make it (no
    /// field, no history, no Dictionary — the scenario's own surface line
    /// and today's date).
    func suggest(_ c: Checkpoint, surface: String, engine: LlamaEngine, length: LengthPreset) async throws
        -> (shown: String?, reason: String?) {
        guard SuggestionText.shouldSuggest(before: c.before, after: nil) else { return (nil, "gate") }
        let heal = TokenHealing.split(c.before)
        let prompt = TypingPrompt.render(TypingContext(before: heal.prompt, surfaceLine: surface, date: Date()))
        var wordBoundary = false
        while true {
            var judge = SuggestionJudge(forced: heal.forced, before: c.before, length: length,
                                        wordBoundary: wordBoundary, isRealWord: Self.isRealWord)
            var raw = ""
            var shown: String?
            var outcome: (String?, String?)?
            for try await piece in await engine.complete(prompt: prompt, maxTokens: length.maxTokens,
                                                              forcing: heal.forced, wordBoundary: wordBoundary) {
                raw += piece
                switch judge.judge(raw, final: false) {
                case .wait: continue
                case .show(let text): shown = text
                case .reject(let reason): outcome = (nil, reason)
                case .retryWithBoundary: outcome = (nil, "retry")
                }
                if outcome != nil { break }
            }
            if outcome == nil {
                switch judge.judge(raw, final: true) {
                case .show(let text): shown = text
                case .reject(let reason): outcome = (nil, reason)
                case .retryWithBoundary: outcome = (nil, "retry")
                case .wait: break
                }
            }
            if outcome?.1 == "retry", !wordBoundary { wordBoundary = true; continue }
            return outcome ?? (shown, shown == nil ? "nothing" : nil)
        }
    }

    // MARK: - Run

    func testReplay() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["PUSH_TYPE_EVAL"] == "1", let dir = env["PUSH_TYPE_MODELS_DIR"] else {
            throw XCTSkip("set PUSH_TYPE_EVAL=1 and PUSH_TYPE_MODELS_DIR to run the replay eval")
        }
        let wanted = env["PUSH_TYPE_EVAL_MODELS"]?.split(separator: ",").map(String.init)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scenarios = try String(contentsOf: repo.appendingPathComponent("eval/autocomplete_scenarios.jsonl"), encoding: .utf8)
            .split(separator: "\n").map { try JSONDecoder().decode(Scenario.self, from: Data($0.utf8)) }

        var report = "# Replay eval (app pipeline)\n\nGenerated by `TypingReplayEvalTests` on \(Date().formatted()).\n"
        report += "Hit = the first word suggested is the word the scenario goes on with. New numbers = digits or markup the text never had (often fine, like “10 minutes”; sometimes invented, like “iOS 10.3.2”).\n\n"
        report += "| Model | Variant | Checkpoints | Shown | Hit | New numbers | Median ms |\n|---|---|---|---|---|---|---|\n"
        var samples = ""

        for model in TypingModel.allCases where wanted?.contains(model.rawValue) ?? true {
            let path = ((dir as NSString).expandingTildeInPath as NSString).appendingPathComponent(model.file)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let engine = LlamaEngine()
            try await engine.load(path: path)
            for try await _ in await engine.complete(prompt: "Hello", maxTokens: 1) {}   // compile the GPU code
            let length = LengthPreset.short.clamped(to: model)
            var results: [Result] = []
            for scenario in scenarios {
                for c in Self.checkpoints(scenario) {
                    let start = Date()
                    let (shown, reason) = try await suggest(c, surface: scenario.surface, engine: engine, length: length)
                    results.append(Result(checkpoint: c, shown: shown, reason: reason,
                                          ms: Date().timeIntervalSince(start) * 1000))
                }
            }
            await engine.unload()

            for variant in Variant.allCases {
                let group = results.filter { $0.checkpoint.variant == variant }
                guard !group.isEmpty else { continue }
                let shown = group.filter { $0.shown != nil }.count
                let hits = group.filter(\.hit).count
                let junk = group.filter(\.junk).count
                let median = group.map(\.ms).sorted()[group.count / 2]
                report += "| \(model.displayName) | \(variant.rawValue) | \(group.count) | \(shown) | \(hits) | \(junk) | \(Int(median)) |\n"
            }
            let reasons = Dictionary(grouping: results.compactMap(\.reason), by: { $0 }).mapValues(\.count)
            samples += "\n## \(model.displayName)\n\nNo suggestion: \(reasons.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))\n\n"
            samples += "| Scenario | Variant | Caret | Suggested | Target | Hit |\n|---|---|---|---|---|---|\n"
            for r in results {
                let caret = String(r.checkpoint.before.suffix(32)).replacingOccurrences(of: "\n", with: "⏎")
                let shown = (r.shown ?? "— \(r.reason ?? "")").replacingOccurrences(of: "|", with: "\\|")
                samples += "| \(r.checkpoint.scenario) | \(r.checkpoint.variant.rawValue) | …\(caret.debugDescription.dropFirst().dropLast()) | \(shown.debugDescription.dropFirst().dropLast()) | \(r.checkpoint.target) | \(r.hit ? "✓" : "") |\n"
            }
        }
        let out = repo.appendingPathComponent("eval/results/replay-latest.md")
        try (report + samples).write(to: out, atomically: true, encoding: .utf8)
        print(report)
    }

    // MARK: - Pure checks of the harness itself

    func testCheckpointsCoverWordSpaceAndMidWord() {
        let s = Scenario(id: "x", surface: "", before: "we need the artwork", expected: "by Wednesday", midword: nil)
        let c = Self.checkpoints(s)
        XCTAssertEqual(c.map(\.variant), [.word, .space])     // "by" is too short for a mid-word stop
        XCTAssertEqual(c[1].before, "we need the artwork ")
        let m = Self.checkpoints(Scenario(id: "y", surface: "", before: "send me the latest", expected: "mockups now", midword: nil))
        XCTAssertEqual(m.last?.before, "send me the latest mo")
        XCTAssertEqual(m.last?.target, "mockups")
    }

    func testHitScoring() {
        let mid = Checkpoint(scenario: "", variant: .mid, before: "really appreci", target: "appreciate", typed: "appreci")
        XCTAssertTrue(Result(checkpoint: mid, shown: "ate it", reason: nil, ms: 0).hit)
        let word = Checkpoint(scenario: "", variant: .word, before: "the artwork", target: "by", typed: "")
        XCTAssertTrue(Result(checkpoint: word, shown: " by Friday.", reason: nil, ms: 0).hit)
        XCTAssertFalse(Result(checkpoint: word, shown: " before", reason: nil, ms: 0).hit)
        XCTAssertTrue(Result(checkpoint: word, shown: " 2018.", reason: nil, ms: 0).junk)
    }
}
