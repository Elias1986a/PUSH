import XCTest
@testable import PUSHCore

final class TypingSuggestionTextTests: XCTestCase {
    func testCutsAtNewlineAndWordLimit() {
        XCTAssertEqual(SuggestionText.clean(" ups for the onboarding flow today\nNext", maxWords: 4), " ups for the onboarding")
    }

    func testKeepsTheModelsOwnSpacingAndTrimsTheEnd() {
        XCTAssertEqual(SuggestionText.clean("ate it.  ", maxWords: 6), "ate it.")
    }

    func testRejectsEmptyOrPunctuationOnly() {
        XCTAssertNil(SuggestionText.clean("  \n", maxWords: 6))
        XCTAssertNil(SuggestionText.clean(" ...", maxWords: 6))
        XCTAssertNil(SuggestionText.clean("\nlater text", maxWords: 6))
    }

    func testRejectsPrefaceLeaks() {
        XCTAssertNil(SuggestionText.clean(" Format: chat; App: Slack", maxWords: 6))
        XCTAssertNil(SuggestionText.clean(" see the Title: field", maxWords: 6))
    }

    func testNextChunkIsOneWordWithItsLeadingSpace() {
        XCTAssertEqual(SuggestionText.nextChunk(of: " for the flow"), " for")
        XCTAssertEqual(SuggestionText.nextChunk(of: "ups for"), "ups")
        XCTAssertEqual(SuggestionText.nextChunk(of: " flow."), " flow.")
    }

    func testRemainderAfterTyping() {
        // User typed "f" while " for the flow" was showing.
        XCTAssertEqual(SuggestionText.remainder(of: " for the flow", afterTyping: " f"), "or the flow")
        XCTAssertNil(SuggestionText.remainder(of: " for the flow", afterTyping: " x"))
    }

    func testRemainderIsNilOnceEverythingIsTyped() {
        XCTAssertNil(SuggestionText.remainder(of: " for", afterTyping: " for"))
    }
}
