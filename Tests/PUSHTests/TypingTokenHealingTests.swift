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
}
