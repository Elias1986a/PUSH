import XCTest
@testable import PUSHCore

final class TypingForcedStartTests: XCTestCase {
    private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    func testTokensInsideTheForcedText() {
        var f = ForcedStart(" appreci")
        XCTAssertTrue(f.fits(bytes(" app")))
        XCTAssertFalse(f.fits(bytes(" the")))
        f.advance(by: bytes(" app"))
        XCTAssertEqual(f.remaining, bytes("reci"))
        XCTAssertTrue(f.fits(bytes("reciate")))       // runs past the forced text
        f.advance(by: bytes("reciate"))
        XCTAssertTrue(f.isDone)
        XCTAssertTrue(f.fits(bytes("\n")))            // anything goes once it is done
    }

    func testWordBoundaryAfterTheForcedText() {
        var f = ForcedStart("Hello", wordBoundary: true)
        XCTAssertFalse(f.fits(bytes("Hellou")))
        XCTAssertTrue(f.fits(bytes("Hello,")))
        XCTAssertTrue(f.fits(bytes("Hello")))         // exactly the word: the boundary is still owed
        f.advance(by: bytes("Hello"))
        XCTAssertFalse(f.isDone)
        XCTAssertFalse(f.fits(bytes("u")))
        XCTAssertTrue(f.fits(bytes("’s")))
        XCTAssertTrue(f.fits(bytes(" there")))
        f.advance(by: bytes(" there"))
        XCTAssertTrue(f.isDone)
    }

    func testEmptyTokensAndEmptyForcing() {
        XCTAssertFalse(ForcedStart(" x").fits([]))    // end of generation before the forced text
        XCTAssertTrue(ForcedStart("").isDone)
        XCTAssertTrue(ForcedStart("", wordBoundary: true).isDone)
    }

    func testGrammarForWhatIsLeft() {
        var f = ForcedStart(" appreci")
        f.advance(by: bytes(" app"))
        XCTAssertEqual(f.grammar, TokenHealing.grammar(forcing: "reci"))
        var g = ForcedStart("Hello", wordBoundary: true)
        g.advance(by: bytes("Hello"))
        XCTAssertEqual(g.grammar, #"root ::=  [ ,.!?;:'"’)] ([^\n] | "\n")*"#)
        var split = ForcedStart(" café")
        split.advance(by: Array(bytes(" caf\u{C3}".replacingOccurrences(of: "\u{C3}", with: "")) + [0xC3]))
        XCTAssertNil(split.grammar)                   // half a character left
    }
}
