import XCTest
@testable import PUSHCore

final class TypingLengthPresetTests: XCTestCase {
    func testCutsAtTheTopOfTheRange() {
        XCTAssertEqual(LengthPreset.short.trim(" one two three four five six seven eight nine"),
                       " one two three four five six seven")
    }

    func testSentenceEndAlwaysStops() {
        // Phase 0: past the first sentence every model drifts.
        XCTAssertEqual(LengthPreset.long.trim("ate it. I'm really excited to be here"), "ate it.")
        XCTAssertEqual(LengthPreset.short.trim(" done? Then we go"), " done?")
    }

    func testClauseBreakStopsOnlyInsideTheRange() {
        // 4–7: a comma after word 2 is too early, after word 5 is in range.
        XCTAssertEqual(LengthPreset.short.trim(" yes, the new artwork is late, so we wait"),
                       " yes, the new artwork is late,")
        XCTAssertEqual(LengthPreset.tiny.trim(" milk, eggs and bread"), " milk,")
    }

    func testShorterThanTheRangeIsLeftAlone() {
        XCTAssertEqual(LengthPreset.medium.trim(" the team"), " the team")
    }

    func testDecimalsAndTimesAreNotSentenceEnds() {
        XCTAssertEqual(LengthPreset.short.trim(" 3.5 percent at 4.30 today and tomorrow too"),
                       " 3.5 percent at 4.30 today and tomorrow")
    }

    func testTokenBudgetGrowsWithThePreset() {
        XCTAssertEqual(LengthPreset.allCases.map(\.maxTokens), LengthPreset.allCases.map(\.maxTokens).sorted())
        XCTAssertGreaterThanOrEqual(LengthPreset.long.maxTokens, 2 * 20)
    }
}
