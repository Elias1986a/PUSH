import XCTest
@testable import PUSHCore

final class TypingKeystrokeBufferTests: XCTestCase {
    private typealias K = KeystrokeBuffer.Key

    func testTypingAndBackspace() {
        var b = KeystrokeBuffer()
        b.apply(.text("Hey, can yu"))
        b.apply(.backspace)
        b.apply(.text("ou"))
        XCTAssertEqual(b.text, "Hey, can you")
    }

    func testResetEmptiesIt() {
        var b = KeystrokeBuffer()
        b.apply(.text("abc"))
        b.apply(.reset)
        XCTAssertEqual(b.text, "")
    }

    func testBackspacePastTheStartIsHarmless() {
        var b = KeystrokeBuffer()
        b.apply(.backspace)
        b.apply(.text("x"))
        XCTAssertEqual(b.text, "x")
    }

    func testKeepsOnlyTheTail() {
        var b = KeystrokeBuffer(limit: 10)
        b.apply(.text("0123456789abc"))
        XCTAssertEqual(b.text, "3456789abc")
    }

    func testClassifiesKeys() {
        XCTAssertEqual(K.classify(keyCode: 0, command: false, control: false, characters: "a"), .text("a"))
        XCTAssertEqual(K.classify(keyCode: 0, command: false, control: false, characters: "é"), .text("é"))
        XCTAssertEqual(K.classify(keyCode: 51, command: false, control: false, characters: "\u{7f}"), .backspace)
        XCTAssertEqual(K.classify(keyCode: 36, command: false, control: false, characters: "\r"), .text("\n"))
        // Anything that moves the caret or edits elsewhere: we no longer know the text.
        for code: Int64 in [123, 124, 125, 126, 115, 119, 116, 121, 117] {
            XCTAssertEqual(K.classify(keyCode: code, command: false, control: false, characters: nil), .reset, "\(code)")
        }
        XCTAssertEqual(K.classify(keyCode: 9, command: true, control: false, characters: "v"), .reset)   // ⌘V
        XCTAssertEqual(K.classify(keyCode: 0, command: false, control: true, characters: "\u{01}"), .reset)
        // Bare modifiers and function keys change nothing.
        XCTAssertEqual(K.classify(keyCode: 56, command: false, control: false, characters: nil), .ignore)
        XCTAssertEqual(K.classify(keyCode: 122, command: false, control: false, characters: "\u{F704}"), .ignore)
    }
}
