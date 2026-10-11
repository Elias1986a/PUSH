import XCTest
@testable import PUSHCore

final class TypingPromptWindowTests: XCTestCase {
    func testWholeTextWhenItFits() {
        XCTAssertEqual(PromptWindow.start(length: 800, maximum: 6_000), 0)
    }

    func testStartMovesInStepsNotPerKeystroke() {
        // 6,000 max, 512 step: from 6,001 to 6,512 characters the start stays put,
        // so the model's cached work on the window keeps matching.
        let a = PromptWindow.start(length: 6_001, maximum: 6_000)
        let b = PromptWindow.start(length: 6_300, maximum: 6_000)
        let c = PromptWindow.start(length: 6_512, maximum: 6_000)
        XCTAssertEqual(a, 512)
        XCTAssertEqual(a, b)
        XCTAssertEqual(b, c)
        XCTAssertEqual(PromptWindow.start(length: 6_513, maximum: 6_000), 1_024)
    }

    func testWindowNeverExceedsTheMaximum() {
        for length in stride(from: 0, to: 20_000, by: 97) {
            let start = PromptWindow.start(length: length, maximum: 6_000)
            XCTAssertLessThanOrEqual(length - start, 6_000)
            XCTAssertGreaterThanOrEqual(length - start, min(length, 6_000 - 512))
        }
    }
}
