import XCTest
@testable import PUSHCore

final class TypingPromptBudgetTests: XCTestCase {
    func testHighestPriorityFilledFirstAndOrderPreserved() {
        let out = PromptBudget.fit([
            .init(name: "a", text: "AAAA", priority: 10, keep: .start),
            .init(name: "p", text: "PPPPPP", priority: 100, keep: .end),
        ], total: 8)
        XCTAssertEqual(out.map(\.name), ["a", "p"])
        XCTAssertEqual(out.last!.text, "PPPPPP")
        XCTAssertEqual(out.first!.text, "A")        // 8 - 6 - 1 separator = 1
    }

    func testKeepEndTrimsFromTheFront() {
        let out = PromptBudget.fit([.init(name: "p", text: "hello world", priority: 100, keep: .end)], total: 5)
        XCTAssertEqual(out.first!.text, "world")
    }

    func testAllOrNothingSectionIsDroppedWhole() {
        let out = PromptBudget.fit([
            .init(name: "p", text: "PPPP", priority: 100, keep: .end),
            .init(name: "q", text: "“quoted”", priority: 50, keep: .start, allOrNothing: true),
        ], total: 8)
        XCTAssertEqual(out.map(\.name), ["p"])
    }

    func testSectionCap() {
        let out = PromptBudget.fit([.init(name: "a", text: "abcdef", priority: 1, keep: .start, cap: 3)], total: 100)
        XCTAssertEqual(out.first!.text, "abc")
    }

    func testEqualPrioritiesKeepInputOrderForFilling() {
        let out = PromptBudget.fit([
            .init(name: "x", text: "XXXX", priority: 5, keep: .start),
            .init(name: "y", text: "YYYY", priority: 5, keep: .start),
        ], total: 6)
        // x is visited first (stable), takes 4; y gets 6 - 4 - 1 = 1.
        XCTAssertEqual(out.map(\.text), ["XXXX", "Y"])
    }

    func testEmptyAndZeroAllowanceSectionsAreDropped() {
        let out = PromptBudget.fit([
            .init(name: "p", text: "PPPP", priority: 100, keep: .end),
            .init(name: "e", text: "", priority: 90, keep: .start),
            .init(name: "z", text: "ZZ", priority: 80, keep: .start),
        ], total: 5)
        // After p (4) only 1 is left: the separator alone, no room for z.
        XCTAssertEqual(out.map(\.name), ["p"])
    }
}
