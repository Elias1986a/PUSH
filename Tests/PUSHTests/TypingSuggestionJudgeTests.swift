import XCTest
@testable import PUSHCore

final class TypingSuggestionJudgeTests: XCTestCase {
    private let words: Set<String> = ["appreciate", "congratulations", "hello", "the", "there"]

    private func judge(before: String) -> SuggestionJudge {
        let heal = TokenHealing.split(before)
        return SuggestionJudge(forced: heal.forced, before: before, length: .medium, wordBoundary: false,
                               isRealWord: { [words] in words.contains($0.lowercased()) })
    }

    func testAFinishedWordShowsBeforeItEnds() {
        var j = judge(before: "I really appreci")
        XCTAssertEqual(j.judge(" appreciat", final: false), .wait)          // not a word yet
        XCTAssertEqual(j.judge(" appreciate", final: false), .show("ate"))  // a word: shown a step sooner
        XCTAssertEqual(j.judge(" appreciate it", final: false), .show("ate it"))
    }

    func testAGluedNonWordStillRetries() {
        var j = judge(before: "Oh hello")
        XCTAssertEqual(j.judge(" hellou", final: false), .wait)
        XCTAssertEqual(j.judge(" hellou there", final: false), .retryWithBoundary)
    }

    func testAShownWordThatGrowsIntoANonWordRetries() {
        var j = judge(before: "Many congr")
        XCTAssertEqual(j.judge(" congratulations", final: false), .show("atulations"))
        XCTAssertEqual(j.judge(" congratulationsz ", final: false), .retryWithBoundary)
    }

    func testTheForcedWordAloneShowsNothingYet() {
        var j = judge(before: "about the")
        XCTAssertEqual(j.judge(" the", final: false), .wait)
        XCTAssertEqual(j.judge(" the meeting", final: false), .show(" meeting"))
    }
}
