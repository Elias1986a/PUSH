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
        for code: Int64 in [123, 124, 125, 126, 115, 119, 116, 121, 117, 48] {
            XCTAssertEqual(K.classify(keyCode: code, command: false, control: false, characters: nil), .reset, "\(code)")
        }
        XCTAssertEqual(K.classify(keyCode: 9, command: true, control: false, characters: "v"), .reset)   // ⌘V
        XCTAssertEqual(K.classify(keyCode: 0, command: false, control: true, characters: "\u{01}"), .reset)
        // Bare modifiers and function keys change nothing.
        XCTAssertEqual(K.classify(keyCode: 56, command: false, control: false, characters: nil), .ignore)
        XCTAssertEqual(K.classify(keyCode: 122, command: false, control: false, characters: "\u{F704}"), .ignore)
    }

    // MARK: - Whose text it is

    func testKeepsTheTextOfTheFieldItWasTypedIn() {
        var b = KeystrokeBuffer()
        b.apply(.text("Hey, can you"))
        b.focus(on: 1, isSecure: false)   // keys before the first read belong nowhere
        b.apply(.text("Hey, can you"))
        XCTAssertFalse(b.focus(on: 1, isSecure: false))
        XCTAssertEqual(b.text, "Hey, can you")
    }

    func testAnotherFieldStartsEmpty() {
        var b = KeystrokeBuffer()
        b.focus(on: 1, isSecure: false)
        b.apply(.text("from the first field"))
        XCTAssertTrue(b.focus(on: 2, isSecure: false))
        XCTAssertEqual(b.text, "")
    }

    /// The review's case: a password, Tab, then a field Accessibility cannot
    /// read, whose "text before the caret" is this buffer.
    func testPasswordThenTabLeavesNothing() {
        var b = KeystrokeBuffer()
        b.focus(on: 1, isSecure: false)                 // the username field
        b.apply(.text("hunter2"))                       // typed too fast for a read
        b.apply(K.classify(keyCode: 48, command: false, control: false, characters: "\t"))
        b.apply(.text("Hi"))
        b.focus(on: 3, isSecure: false)
        XCTAssertFalse(b.text.contains("hunter"))
    }

    func testPasswordThenReturnLeavesNothing() {
        var b = KeystrokeBuffer()
        b.apply(.text("hunter2\n"))                     // before any read, then submitted
        b.focus(on: 3, isSecure: false)
        XCTAssertEqual(b.text, "")
    }

    func testNothingIsKeptFromAPasswordField() {
        var b = KeystrokeBuffer()
        b.focus(on: 2, isSecure: true)
        b.apply(.text("hunter2"))
        b.focus(on: 2, isSecure: true)                  // read again, still that field
        XCTAssertEqual(b.text, "")
    }
}
