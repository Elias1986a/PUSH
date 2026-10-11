import XCTest
@testable import PUSHCore

final class TypingSuggestionTextTests: XCTestCase {
    func testCutsAtNewlineAndWordLimit() {
        XCTAssertEqual(SuggestionText.clean(" ups for the onboarding flow today\nNext", maxWords: 4), " ups for the onboarding")
    }

    func testBarePunctuationIsNotAWord() {
        XCTAssertEqual(SuggestionText.clean(", everyone. Today we", maxWords: 1), ", everyone.")
        XCTAssertEqual(LengthPreset.tiny.trim(" - one two three four"), " - one two three")
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

    func testWaitsForThreeWords() {
        XCTAssertFalse(SuggestionText.shouldSuggest(before: "hello", after: nil))
        XCTAssertFalse(SuggestionText.shouldSuggest(before: "Hello, I", after: ""))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "Hello, I wanted", after: nil))
        XCTAssertFalse(SuggestionText.shouldSuggest(before: "   \n", after: nil))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "Thanks,\n", after: nil))   // sign-off: the name is next
    }

    func testNotWithTheCaretInsideAWord() {
        // "hel|lo world": anything suggested would splice into "lo".
        XCTAssertFalse(SuggestionText.shouldSuggest(before: "we should say hel", after: "lo world"))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "we should say hello", after: " world"))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "we should say hello ", after: "world"))
        XCTAssertTrue(SuggestionText.shouldSuggest(before: "we should say hel", after: "\nnext line"))
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

final class TypingSuggestionSafetyTests: XCTestCase {
    func testRejectsAnInventedPersona() {
        XCTAssertTrue(SuggestionText.isUnwanted(", I'm a 17 year old girl.", before: "Hello"))
        XCTAssertTrue(SuggestionText.isUnwanted(" I am a 20-year-old guy", before: "Hi"))
        XCTAssertTrue(SuggestionText.isUnwanted(", my name is Sarah and", before: "Hello"))
        XCTAssertTrue(SuggestionText.isUnwanted(" I'm 15 and I", before: "Hey"))
    }

    func testOrdinaryTextPasses() {
        XCTAssertFalse(SuggestionText.isUnwanted(", how are you?", before: "Hello"))
        XCTAssertFalse(SuggestionText.isUnwanted(" I'm running about 10 minutes late", before: "Sorry,"))
        XCTAssertFalse(SuggestionText.isUnwanted(" the 3 year plan", before: "We reviewed"))
        XCTAssertFalse(SuggestionText.isUnwanted(" I'm tired and need a break", before: "Honestly"))
        XCTAssertFalse(SuggestionText.isUnwanted(" I am from the product team", before: "Hi,"))
    }

    func testCatchesAPersonaCompletedAcrossAccepts() {
        // ", I'm" then "a" were accepted; the model now offers the age.
        XCTAssertTrue(SuggestionText.isUnwanted(" 17 year old girl", before: "Hello, I'm a"))
        XCTAssertTrue(SuggestionText.isUnwanted(" Sarah", before: "Hi, my name is"))
    }

    func testNeverFillsInFactsAboutTheUser() {
        // Only the user knows who they are; a model can only invent it.
        for before in ["hello, I am a", "Hi, I'm", "I am from", "I'm from the", "my name is", "I work at",
                       "I live in", "I work for a", "I study at"] {
            XCTAssertTrue(SuggestionText.isUnwanted(" student of the university", before: before), before)
        }
    }

    func testOrdinarySentencesWithIStillWork() {
        XCTAssertFalse(SuggestionText.isUnwanted(" to ask you something", before: "I wanted"))
        XCTAssertFalse(SuggestionText.isUnwanted(" happy to help", before: "I am"))
        XCTAssertFalse(SuggestionText.isUnwanted(" sure we can", before: "I'm not"))
    }

    func testTheUsersOwnIntroductionIsTheirs() {
        // The user typed the whole pattern themselves: continuing it is fine.
        XCTAssertFalse(SuggestionText.isUnwanted(" and I live in Boston", before: "I'm a 40 year old dad"))
    }

    func testWhatTheUserWroteThemselvesIsNotPolicedTwice() {
        // Continuing the user's own sentence about their age is fine.
        XCTAssertFalse(SuggestionText.isUnwanted(" year old daughter", before: "My 7"))
    }

    func testRejectsExplicitWordsTheUserDidNotType() {
        XCTAssertTrue(SuggestionText.isUnwanted(" sexy pics", before: "Check out my"))
        XCTAssertFalse(SuggestionText.isUnwanted(" Essex office", before: "Meet at the"))   // word, not substring
    }

}

final class TypingSuggestionWebJunkTests: XCTestCase {
    func testRejectsMarkupHandlesAndLinks() {
        XCTAssertTrue(SuggestionText.isUnwanted("<strong>@jason-m-smith</strong>,", before: "Hello,"))
        XCTAssertTrue(SuggestionText.isUnwanted(" @jason", before: "Thanks"))
        XCTAssertTrue(SuggestionText.isUnwanted(" https://example.com", before: "See"))
        XCTAssertTrue(SuggestionText.isUnwanted(" www.site.com", before: "Visit"))
        XCTAssertTrue(SuggestionText.isUnwanted(" {{name}}", before: "Dear"))
    }

    func testAllowedWhenTheUserIsAlreadyWritingThatKindOfThing() {
        XCTAssertFalse(SuggestionText.isUnwanted("ason can you check", before: "cc @j"))
        XCTAssertFalse(SuggestionText.isUnwanted(" docs/setup", before: "See https://example.com/"))
        XCTAssertFalse(SuggestionText.isUnwanted("div>", before: "<div></"))
    }

    func testOrdinaryPunctuationIsFine() {
        XCTAssertFalse(SuggestionText.isUnwanted(", how are you?", before: "Hello"))
        XCTAssertFalse(SuggestionText.isUnwanted(" (by Friday)", before: "Send it"))
    }
}

final class TypingSuggestionRepeatTests: XCTestCase {
    func testRejectsStartingWithTheWordJustTyped() {
        XCTAssertTrue(SuggestionText.repeats(" to see you", before: "and would love to"))
        XCTAssertTrue(SuggestionText.repeats(" the city", before: "We will be in the"))
        XCTAssertFalse(SuggestionText.repeats(" see you", before: "and would love to"))
    }

    func testRejectsBackToBackRepeats() {
        XCTAssertTrue(SuggestionText.repeats(" 3 3 3 3", before: "in the city for"))
        XCTAssertTrue(SuggestionText.repeats(" days. We We will", before: "for 3"))
        XCTAssertFalse(SuggestionText.repeats(" had had enough", before: "she"))   // rare but real: allowed once
    }

    func testRejectsRestartingTheWordsJustWritten() {
        // Cotabby's rule: the suggestion contains the last four words before the caret.
        XCTAssertTrue(SuggestionText.repeats(". Hi Sarah, thanks for sending", before: "Hi Sarah, thanks for s"))
    }

    func testARepeatedParagraphElsewhereIsFine() {
        // A note that repeats a passage makes reproducing it the right guess
        // (Cotabby: a whole-window rule threw away 168 of 179 completions).
        let before = "We will be in the city for 3 days. Looking forward to it. "
        XCTAssertFalse(SuggestionText.repeats("We will be in the city for", before: before))
    }

    func testRejectsShortLoops() {
        XCTAssertTrue(SuggestionText.repeats(" Hi S. Hi S. Hi S.", before: "Dear team"))
        XCTAssertTrue(SuggestionText.repeats(" go now go now go now", before: "We should"))
    }

    func testMidWordContinuationIsNotARepeat() {
        // "appreci" + "ate it" — the suggestion continues the word, it does not repeat it.
        XCTAssertFalse(SuggestionText.repeats("ate it.", before: "really appreci"))
    }
}

final class TypingSuggestionScaffoldingTests: XCTestCase {
    func testRejectsClosingPunctuationRightAfterATypedSpace() {
        XCTAssertTrue(SuggestionText.isUnwanted(", regards", before: "Best "))
        XCTAssertFalse(SuggestionText.isUnwanted(", regards", before: "Best"))
    }

    func testRejectsForumResidueAndTalkBack() {
        XCTAssertTrue(SuggestionText.isUnwanted(" [User 0001] said", before: "I think"))
        XCTAssertTrue(SuggestionText.isUnwanted(" 12:03 PM · 1 min read · Reply", before: "Great post"))
        XCTAssertTrue(SuggestionText.isUnwanted(" As an AI, I cannot", before: "Can you"))
        XCTAssertTrue(SuggestionText.isUnwanted(" I'm not sure what you mean", before: "Okay so"))
    }
}

final class TypingCaretWordsTests: XCTestCase {
    func testSplitsTheFinishedWordFromTheOneBeingTyped() {
        XCTAssertEqual(SuggestionText.caretWords("can we move teh ").finished, "teh")
        XCTAssertNil(SuggestionText.caretWords("can we move teh ").partial)
        XCTAssertEqual(SuggestionText.caretWords("can we move teh mee").partial, "mee")
        XCTAssertEqual(SuggestionText.caretWords("can we move teh mee").finished, "teh")
        XCTAssertEqual(SuggestionText.caretWords("Thanks, Sarah.").finished, "Sarah")
        XCTAssertNil(SuggestionText.caretWords("").finished)
    }

    func testTrailingSpaceOnlyAtTheEndOfALine() {
        XCTAssertTrue(SuggestionText.needsTrailingSpace(finishing: " weekend?", nextInField: nil))
        XCTAssertTrue(SuggestionText.needsTrailingSpace(finishing: "ate", nextInField: "\n"))
        XCTAssertFalse(SuggestionText.needsTrailingSpace(finishing: "the ", nextInField: nil))
        XCTAssertFalse(SuggestionText.needsTrailingSpace(finishing: " team", nextInField: " "))
        XCTAssertFalse(SuggestionText.needsTrailingSpace(finishing: " team", nextInField: "x"))
    }
}
