import XCTest
@testable import PUSH

/// Tests for the pill's live-transcript tail formatting.
final class LiveTranscriptTests: XCTestCase {

    func testShortTextPassesThroughUnchanged() {
        XCTAssertEqual(LiveTranscript.tail(of: "hello there", limit: 64), "hello there")
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(LiveTranscript.tail(of: "  hello there \n", limit: 64), "hello there")
    }

    func testEmptyTextStaysEmpty() {
        XCTAssertEqual(LiveTranscript.tail(of: "", limit: 64), "")
        XCTAssertEqual(LiveTranscript.tail(of: "   ", limit: 64), "")
    }

    func testTextAtTheLimitIsNotTrimmed() {
        let exact = String(repeating: "a", count: 10)
        XCTAssertEqual(LiveTranscript.tail(of: exact, limit: 10), exact)
    }

    func testLongTextKeepsTheTailWithAnEllipsis() {
        let result = LiveTranscript.tail(of: "one two three four five six", limit: 12)
        XCTAssertTrue(result.hasPrefix("…"), "expected an ellipsis prefix, got \(result)")
        XCTAssertTrue(result.hasSuffix("six"), "expected the newest words, got \(result)")
    }

    func testTailStartsOnAWordBoundary() {
        // A 12-char window over this lands mid-"five"; the cut must move forward
        // to the next whole word rather than showing a word fragment.
        XCTAssertEqual(LiveTranscript.tail(of: "one two three four five six", limit: 12), "…five six")
    }

    func testTailNeverExceedsTheLimitPlusEllipsis() {
        let long = (1...200).map(String.init).joined(separator: " ")
        let result = LiveTranscript.tail(of: long, limit: 64)
        XCTAssertLessThanOrEqual(result.count, 65)
    }

    func testSingleLongWordFallsBackToARawTail() {
        // No boundary to cut on — better to show the tail than nothing.
        let word = String(repeating: "x", count: 50)
        let result = LiveTranscript.tail(of: word, limit: 10)
        XCTAssertEqual(result, "…" + String(repeating: "x", count: 10))
    }

    func testNonPositiveLimitYieldsEmpty() {
        XCTAssertEqual(LiveTranscript.tail(of: "hello", limit: 0), "")
    }
}
