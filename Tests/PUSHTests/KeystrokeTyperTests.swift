import XCTest
@testable import PUSH

final class KeystrokeTyperTests: XCTestCase {
    func testShortTextIsOneEvent() {
        XCTAssertEqual(KeystrokeTyper.chunks(of: "hello wörld 👋"), ["hello wörld 👋"])
    }

    func testChunksStayWithinTwentyUnitsAndRejoin() {
        let text = "naïve café 🎬 typed across twenty-unit chunks 👋🏽"
        let chunks = KeystrokeTyper.chunks(of: text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 20 })
        XCTAssertGreaterThan(chunks.count, 1)
    }

    func testEmojiIsNeverSplit() {
        // 19 letters, then a 4-unit emoji with a skin tone: the emoji must move
        // to the next event whole.
        let chunks = KeystrokeTyper.chunks(of: String(repeating: "a", count: 19) + "👋🏽")
        XCTAssertEqual(chunks, [String(repeating: "a", count: 19), "👋🏽"])
    }

    func testEmpty() {
        XCTAssertEqual(KeystrokeTyper.chunks(of: ""), [])
    }
}
