import XCTest
@testable import PUSHCore

final class TypingPromptCaretTests: XCTestCase {
    private func move(_ code: Int64, command: Bool = false, option: Bool = false, control: Bool = false) -> PromptCaret.Move? {
        PromptCaret.move(keyCode: code, command: command, option: option, control: control)
    }

    func testKeysToMoves() {
        XCTAssertEqual(move(123), .left)
        XCTAssertEqual(move(124), .right)
        XCTAssertEqual(move(124, command: true), .toEnd)
        XCTAssertEqual(move(124, option: true), .wordRight)
        XCTAssertEqual(move(123, option: true), .elsewhere)
        XCTAssertEqual(move(126), .vertical)
        XCTAssertEqual(move(119), .toEnd)
        XCTAssertEqual(move(14, control: true), .toEnd)     // ⌃E
        XCTAssertEqual(move(0, control: true), .elsewhere)  // ⌃A
        XCTAssertEqual(move(117), .deleteForward)
        XCTAssertNil(move(0))                               // "a"
        XCTAssertNil(move(51))                              // backspace stays where it is
    }

    func testCountsBackToTheEnd() {
        var caret = PromptCaret()
        caret.apply(.left); caret.apply(.left)
        XCTAssertFalse(caret.atEnd)
        caret.apply(.right)
        XCTAssertFalse(caret.atEnd)
        caret.apply(.right)
        XCTAssertTrue(caret.atEnd)
        caret.apply(.right)                                 // → at the end goes nowhere
        XCTAssertTrue(caret.atEnd)
    }

    func testUnknownUntilClearlyAtTheEnd() {
        var caret = PromptCaret()
        caret.apply(.elsewhere)
        caret.apply(.right)
        XCTAssertFalse(caret.atEnd)                         // still not known
        caret.apply(.toEnd)
        XCTAssertTrue(caret.atEnd)
        caret.apply(.wordRight)                             // a word on from the end: still the end
        XCTAssertTrue(caret.atEnd)
        caret.apply(.left); caret.apply(.wordRight)
        XCTAssertFalse(caret.atEnd)
        caret.reset()                                       // sent or emptied
        XCTAssertTrue(caret.atEnd)
    }

    func testForwardDeleteShortensWhatFollows() {
        var caret = PromptCaret()
        caret.apply(.left)
        caret.apply(.deleteForward)
        XCTAssertTrue(caret.atEnd)
    }
}
