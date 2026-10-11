import XCTest
@testable import PUSHCore

final class TypingTokenHealingTests: XCTestCase {
    func testBacksOffThePartialWord() {
        XCTAssertEqual(TokenHealing.split("so fast, really appreci").prompt, "so fast, really")
        XCTAssertEqual(TokenHealing.split("so fast, really appreci").forced, " appreci")
    }

    func testCompleteWordAtTheCaretIsForcedToo() {
        let h = TokenHealing.split("No worries, take your")
        XCTAssertEqual(h.prompt, "No worries, take")
        XCTAssertEqual(h.forced, " your")
    }

    func testATrailingSpaceMovesIntoTheForcedStart() {
        // A prompt ending in a bare space reads, to a BPE model, as a word
        // boundary nobody writes (" see" is one token): it predicted a line
        // break, so every pause after a space got nothing.
        let h = TokenHealing.split("and would love to ")
        XCTAssertEqual(h.prompt, "and would love to")
        XCTAssertEqual(h.forced, " ")
        XCTAssertEqual(TokenHealing.split("so far,  ").forced, "  ")
    }

    func testNothingToHealAfterPunctuationOrNewline() {
        XCTAssertEqual(TokenHealing.split("Blockers:").forced, "")
        XCTAssertEqual(TokenHealing.split("Thanks,\n").forced, "")
        XCTAssertEqual(TokenHealing.split("Thanks,\n").prompt, "Thanks,\n")
        XCTAssertEqual(TokenHealing.split("").forced, "")
    }

    func testWholeTextIsOnePartialWord() {
        XCTAssertEqual(TokenHealing.split("proj").prompt, "")
        XCTAssertEqual(TokenHealing.split("proj").forced, "proj")
    }

    func testAWordStartingANewLineLeavesTheNewlineInThePrompt() {
        let h = TokenHealing.split("Action items:\nproj")
        XCTAssertEqual(h.prompt, "Action items:\n")
        XCTAssertEqual(h.forced, "proj")
    }

    func testApostrophesAndAccentsStayInTheWord() {
        XCTAssertEqual(TokenHealing.split("I don’").forced, " don’")
        XCTAssertEqual(TokenHealing.split("a nice caf").forced, " caf")
    }

    func testGrammarForcesTheStartThenAllowsAnything() {
        XCTAssertEqual(TokenHealing.grammar(forcing: " appreci"), #"root ::= " appreci" ([^\n] | "\n")*"#)
        XCTAssertNil(TokenHealing.grammar(forcing: ""))
    }

    func testGrammarEscapesQuotesAndBackslashes() {
        XCTAssertEqual(TokenHealing.grammar(forcing: #"say "hi\"#), #"root ::= "say \"hi\\" ([^\n] | "\n")*"#)
    }

    func testStripRemovesTheForcedStart() {
        XCTAssertEqual(TokenHealing.strip(" appreciate it", forced: " appreci"), "ate it")
        XCTAssertEqual(TokenHealing.strip(" your time.", forced: " your"), " time.")
        XCTAssertNil(TokenHealing.strip(" something else", forced: " appreci"))
        XCTAssertEqual(TokenHealing.strip(" for the", forced: ""), " for the")
    }

    func testGluedWordJoinsThePartialWithTheLettersThatFollow() {
        XCTAssertEqual(TokenHealing.gluedWord(forced: " appreci", continuation: "ate it."), "appreciate")
        XCTAssertEqual(TokenHealing.gluedWord(forced: "Hello", continuation: "u, I'm"), "Hellou")
        XCTAssertNil(TokenHealing.gluedWord(forced: "Hello", continuation: ", how are you"))
        XCTAssertNil(TokenHealing.gluedWord(forced: " your", continuation: " time."))
        XCTAssertNil(TokenHealing.gluedWord(forced: "", continuation: "abc"))
    }

    func testBoundaryGrammarForbidsALetterRightAfterTheWord() {
        XCTAssertEqual(TokenHealing.grammar(forcing: "Hello", wordBoundary: true),
                       #"root ::= "Hello" [ ,.!?;:'"’)] ([^\n] | "\n")*"#)
    }
}
