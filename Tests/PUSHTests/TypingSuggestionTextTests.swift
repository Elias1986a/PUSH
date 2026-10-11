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

    func testSuggestsFromTheFirstCharacter() {
        // Like Cotabby: any typed text is enough — a first word just gets the
        // model's ordinary guess at how a sentence goes on.
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "hello", after: nil))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "H", after: ""))
        XCTAssertFalse(SuggestionText.shouldSuggest(before: "   \n", after: nil))
        XCTAssertFalse(SuggestionText.shouldSuggest(before: "", after: nil))
    }

    func testNotWithTheCaretInsideAWord() {
        // "hel|lo world": anything suggested would splice into "lo".
        XCTAssertFalse(SuggestionText.shouldSuggest(before: "say hel", after: "lo world"))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "say hello", after: " world"))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "say hello ", after: "world"))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "say hel", after: "\nnext line"))
    }
}

final class TypingScriptMatchTests: XCTestCase {
    func testRejectsAnotherWritingSystemThanTheText() {
        XCTAssertFalse(SuggestionText.matchesScript(" 你好吗", before: "Hello"))
        XCTAssertFalse(SuggestionText.matchesScript("、こんにちは", before: "hello"))
        XCTAssertFalse(SuggestionText.matchesScript(" 안녕하세요", before: "Hi there"))
        XCTAssertFalse(SuggestionText.matchesScript(" привет", before: "Hello"))
    }

    func testAcceptsTheSameWritingSystem() {
        XCTAssertTrue(SuggestionText.matchesScript(" how are you?", before: "Hello"))
        XCTAssertTrue(SuggestionText.matchesScript(" café à côté", before: "On se voit au"))
        XCTAssertTrue(SuggestionText.matchesScript("ですね", before: "今日はいい天気"))   // kana + kanji are one group
        XCTAssertTrue(SuggestionText.matchesScript(" 3.5% 🎬", before: "It grew"))           // no letters: fine
    }

    func testTextWithoutLettersAcceptsLatinOnly() {
        XCTAssertTrue(SuggestionText.matchesScript(" items", before: "1. "))
        XCTAssertFalse(SuggestionText.matchesScript(" 项目", before: "1. "))
    }
}
