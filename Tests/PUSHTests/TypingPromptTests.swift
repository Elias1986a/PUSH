import XCTest
@testable import PUSHCore

final class TypingPromptTests: XCTestCase {
    private let surface = "Format: chat; App: Slack; Title: #design; Field: Message #design."

    func testNoContextIsJustBefore() {
        XCTAssertEqual(TypingPrompt.render(TypingContext(before: "Hey, can you")), "Hey, can you")
    }

    func testSurfaceFirstThenBlankLineThenBefore() {
        let prompt = TypingPrompt.render(TypingContext(before: "Hey, can you", surfaceLine: surface))
        XCTAssertEqual(prompt, surface + "\n\nHey, can you")
    }

    func testDateFollowsTheSurfaceLine() {
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 11, hour: 12).date!
        let ctx = TypingContext(before: "The launch is planned for", surfaceLine: "Format: email.", date: date)
        XCTAssertEqual(TypingPrompt.render(ctx), "Format: email.\nDate: Sunday, October 11, 2026.\n\nThe launch is planned for")
    }

    func testCaretTextIsTheLastBytesWhateverElseIsThere() {
        let context = TypingContext(before: "Thanks,\n", after: "P.S. see you Friday", surfaceLine: surface,
                                    style: "Short, friendly sentences.", language: "English",
                                    userName: "Elias", clipboard: "launch plan", screen: "Q4 launch plan",
                                    examples: ["Sounds good, ship it."])
        XCTAssertTrue(TypingPrompt.render(context).hasSuffix("\n\nThanks,\n"))
    }

    func testAfterIsQuotedAndCapped() {
        let after = String(repeating: "word ", count: 100)
        let prompt = TypingPrompt.render(TypingContext(before: "Hi", after: after))
        let quote = try! XCTUnwrap(prompt.range(of: "Later in the same passage:\n“"))
        let close = try! XCTUnwrap(prompt.range(of: "”"))
        XCTAssertLessThanOrEqual(prompt.distance(from: quote.upperBound, to: close.lowerBound), 200)
        XCTAssertTrue(prompt.hasSuffix("\n\nHi"))
    }

    func testAfterIsDroppedWholeUnderPressure() {
        let before = String(repeating: "b", count: 1_050)
        let prompt = TypingPrompt.render(TypingContext(before: before, after: "the rest of the passage"), budget: 1_060)
        XCTAssertFalse(prompt.contains("Later in"))
        XCTAssertFalse(prompt.contains("the rest"))
    }

    func testNameOnlyAtASignOff() {
        for signOff in ["Thanks,\n", "Best,", "Cheers,\n", "Kind regards,\n", "Thank you,\n"] {
            XCTAssertTrue(TypingPrompt.render(TypingContext(before: "See you then.\n\n" + signOff, userName: "Elias"))
                .contains("Elias"), signOff)
        }
        XCTAssertFalse(TypingPrompt.render(TypingContext(before: "Thanks for the help", userName: "Elias"))
            .contains("Elias"))
        XCTAssertFalse(TypingPrompt.render(TypingContext(before: "All the best, and", userName: "Elias"))
            .contains("Elias"))
    }

    func testBudgetHeldAndBeforeKeepsItsLast1000() {
        let before = (0..<2_000).map { "w\($0) " }.joined()
        let prompt = TypingPrompt.render(TypingContext(before: before, surfaceLine: surface), budget: 1_500)
        XCTAssertLessThanOrEqual(prompt.count, 1_500)
        XCTAssertTrue(prompt.hasSuffix(String(before.suffix(1_000))))
    }

    func testDefaultBudgetIs6000() {
        let before = String(repeating: "x", count: 9_000)
        XCTAssertEqual(TypingPrompt.render(TypingContext(before: before)).count, 6_000)
    }

    func testBudgetBelowTheFloorStillKeeps1000() {
        let before = String(repeating: "x", count: 3_000)
        XCTAssertEqual(TypingPrompt.render(TypingContext(before: before), budget: 10).count, 1_000)
    }
}
