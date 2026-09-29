import XCTest
@testable import PUSHCore

/// Scores `resolveSelfCorrections` against `eval/self_corrections.jsonl`.
///
/// A measurement, not a gate: it never fails, it prints `EVAL|` lines. The set
/// is the bar a model-based resolver has to clear before it ships (NOTES,
/// "Smarter self-correction"), and running the same file through today's rules
/// is what gives that bar a number. `swift test --filter SelfCorrectionEval`.
final class SelfCorrectionEvalTests: XCTestCase {
    private struct Case: Decodable {
        let category: String
        let input: String
        let expected: String
    }

    func testScoreTheRulesAgainstTheEvalSet() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("eval/self_corrections.jsonl")
        let cases = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(Case.self, from: Data($0.utf8)) }

        var tally: [String: (pass: Int, total: Int)] = [:]
        for c in cases {
            let got = TranscriptionPipeline.resolveSelfCorrections(c.input)
            let pass = got == c.expected
            tally[c.category, default: (0, 0)].total += 1
            if pass { tally[c.category]!.pass += 1 } else {
                print("EVAL| ✗ [\(c.category)] \(c.input)\nEVAL|     got      \(got)\nEVAL|     expected \(c.expected)")
            }
        }
        for (category, t) in tally.sorted(by: { $0.key < $1.key }) {
            print("EVAL| \(category): \(t.pass)/\(t.total)")
        }
        let passed = tally.values.map(\.pass).reduce(0, +)
        print("EVAL| total: \(passed)/\(cases.count)")
    }
}
