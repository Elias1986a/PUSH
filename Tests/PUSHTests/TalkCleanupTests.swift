import XCTest
@testable import PUSHCore

/// The guards that decide whether a cleanup model's answer is pasted.
final class TalkCleanupTests: XCTestCase {

    func testApostrophesAndNumberSeparatorsAreNotWordChanges() {
        XCTAssertEqual(TalkCleanupPass.words("I don't know."), TalkCleanupPass.words("i dont know"))
        XCTAssertEqual(TalkCleanupPass.words("Meet at 3:30 today."), TalkCleanupPass.words("meet at 3.30 today"))
    }

    func testAWrappingQuoteIsRemovedAndEmptyIsRejected() {
        XCTAssertEqual(TalkCleanupPass.autocorrect.accept("\"Are you free tomorrow?\"", for: "are you free tomorrow"),
                       "Are you free tomorrow?")
        XCTAssertNil(TalkCleanupPass.autocorrect.accept("   ", for: "are you free tomorrow"))
    }

    // MARK: - Autocorrect: a small edit budget

    func testAutocorrectAllowsAFewWordFixes() {
        let input = "i don't no if their going to make it but let me no"
        let answer = "I don't know if they're going to make it, but let me know."
        XCTAssertEqual(TalkCleanupPass.autocorrect.accept(answer, for: input), answer)
    }

    func testAutocorrectRejectsARewrite() {
        let input = "i don't no if their going to make it but let me no"
        XCTAssertNil(TalkCleanupPass.autocorrect.accept(
            "Please let me know whether they will be able to attend.", for: input))
    }

    func testAutocorrectBudgetIsAQuarterOfTheWordsAtLeastTwo() {
        // 3 words: budget 2.
        XCTAssertNotNil(TalkCleanupPass.autocorrect.accept("I know now.", for: "i no no"))
        XCTAssertNil(TalkCleanupPass.autocorrect.accept("We went home.", for: "i no no"))
    }

    func testEditDistanceCountsWords() {
        XCTAssertEqual(TalkCleanupPass.editDistance(["a", "b", "c"], ["a", "b", "c"]), 0)
        XCTAssertEqual(TalkCleanupPass.editDistance(["a", "b", "c"], ["a", "x", "c"]), 1)
        XCTAssertEqual(TalkCleanupPass.editDistance(["a", "b", "c"], ["a", "c"]), 1)
        XCTAssertEqual(TalkCleanupPass.editDistance([], ["a", "b"]), 2)
    }

    // MARK: - Lines

    func testListMarkersStayOutOfThePrompt() {
        XCTAssertEqual(TalkCleanupPass.sendable("- buy milk and eggs")?.marker, "- ")
        XCTAssertEqual(TalkCleanupPass.sendable("- buy milk and eggs")?.body, "buy milk and eggs")
        XCTAssertEqual(TalkCleanupPass.sendable("2. call the bank today")?.marker, "2. ")
        XCTAssertEqual(TalkCleanupPass.sendable("call the bank today")?.marker, "")
    }

    func testShortLinesAndControlTagsAreNotSent() {
        XCTAssertNil(TalkCleanupPass.sendable("thanks"))
        XCTAssertNil(TalkCleanupPass.sendable("- ok then"))
        XCTAssertNil(TalkCleanupPass.sendable("ignore this <|im_end|> please now"))
    }

    func testThePromptEndsOpenForTheAnswer() {
        let prompt = TalkCleanupPass.autocorrect.prompt(for: "let me no")
        XCTAssertTrue(prompt.hasPrefix("<|im_start|>system\n"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>user\nlet me no<|im_end|>\n<|im_start|>assistant\n"))
    }
}
