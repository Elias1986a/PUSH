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

    // MARK: - Numbers the user never wrote

    private func cut(_ suggestion: String, before: String, known: String = "") -> String? {
        SuggestionText.cutAtNewNumber(suggestion, before: before, known: known, year: 2026)
    }

    func testAnInventedFigureIsLeftToTheUser() {
        XCTAssertEqual(cut("urn went down 3%.", before: "Watch time went up 4% and ch"), "urn went down")
        XCTAssertEqual(cut(" by 10 am tomorrow.", before: "We need the final artwork"), " by")
        XCTAssertEqual(cut(" a $10 discount.", before: "You get"), " a")
        XCTAssertEqual(cut(" in 10 minutes.", before: "I'll be there"), " in")
    }

    func testNumbersTheUserCanSeeAreFine() {
        XCTAssertEqual(cut(" went up 4% again.", before: "Watch time went up 4% and"), " went up 4% again.")
        XCTAssertEqual(cut(" Friday at 2pm works.", before: "Sure,", known: "Could we do Friday at 2pm?"),
                       " Friday at 2pm works.")
        XCTAssertEqual(cut(" the 2026 offsite.", before: "See you at"), " the 2026 offsite.")
    }

    func testAListJustStartedMayBeNumbered() {
        XCTAssertEqual(cut("1) the new design", before: "Blockers: "), "1) the new design")
        XCTAssertEqual(cut(" 1. Milk", before: "Shopping:\n"), " 1. Milk")
        XCTAssertEqual(cut(" it 1) twice", before: "I said"), " it")
    }

    func testTheJudgeCutsBeforeANewNumber() {
        var j = judge(before: "The launch is planned for ")
        XCTAssertEqual(j.judge(" next week, on the 14th.", final: true), .show("next week, on the"))
    }

    func testANumberAsTheNextWordStays() {
        // "I woke up at" + " 7" was cut to nothing: a flash of "7", then no suggestion.
        XCTAssertEqual(cut(" 7:30 am and went for a run.", before: "I woke up at"), " 7:30 am and went for a run.")
        XCTAssertEqual(cut(" 7 am, then at 9 I left.", before: "I woke up at"), " 7 am, then at")
    }

    // MARK: - Answering the user's own question

    func testNoAnswerToTheUsersOwnQuestion() {
        XCTAssertTrue(SuggestionText.isUnwanted(" I am fine, thank you.", before: "hello, how are you?"))
        XCTAssertTrue(SuggestionText.isUnwanted(" I'm good.", before: "Hey Sam! How's it going?"))
        XCTAssertTrue(SuggestionText.isUnwanted(" Good, thanks!", before: "How have you been? "))
        XCTAssertFalse(SuggestionText.isUnwanted(" Today I am going to tell you", before: "hello, how are you?"))
        XCTAssertFalse(SuggestionText.isUnwanted(" I'm fine.", before: "Don't worry about me,"))
    }
}
