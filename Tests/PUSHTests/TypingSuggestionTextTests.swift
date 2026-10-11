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

final class TypingSuggestionPolishTests: XCTestCase {
    func testCapitalisesTheFirstWordOfANewSentence() {
        XCTAssertEqual(SuggestionText.polish(" the meeting is at 3.", before: "Can you review it?"), " The meeting is at 3.")
        XCTAssertEqual(SuggestionText.polish("the meeting", before: "Done. "), "The meeting")
        XCTAssertEqual(SuggestionText.polish(" and more", before: "Done!\n"), " And more")
    }

    func testLeavesMidSentenceAlone() {
        XCTAssertEqual(SuggestionText.polish(" the meeting", before: "Can you review"), " the meeting")
        XCTAssertEqual(SuggestionText.polish(" 5 percent", before: "It grew by 3.5"), " 5 percent")
    }

    func testDecimalPointIsNotASentenceEnd() {
        XCTAssertEqual(SuggestionText.polish("5 percent", before: "It grew by 3."), "5 percent")
    }

    func testRejectsACapitalGluedOntoALowercaseWord() {
        // "hello" + "World" (camelCase junk), when the caret sits right after a word.
        XCTAssertNil(SuggestionText.polish("World", before: "hello"))
        XCTAssertEqual(SuggestionText.polish("ate it.", before: "really appreci"), "ate it.")
        XCTAssertEqual(SuggestionText.polish("World", before: "Hello "), "World")
    }

    func testNeedsTwoWordsOfContext() {
        XCTAssertFalse(SuggestionText.hasEnoughContext("hello"))
        XCTAssertFalse(SuggestionText.hasEnoughContext("  hi  "))
        XCTAssertTrue(SuggestionText.hasEnoughContext("hello there"))
        XCTAssertTrue(SuggestionText.hasEnoughContext("Thanks,\n"))  // a sign-off line still counts
    }
}
