import XCTest
@testable import PUSHCore

final class TypoFixTests: XCTestCase {
    private let misspelled: Set<String> = ["recieve", "teh", "definately", "wierd"]
    private let corrections: [String: [String]] = [
        "recieve": ["receive", "relieve"], "teh": ["the", "tech"],
        "definately": ["definitely"], "wierd": ["weird", "wired"],
    ]

    private func fix(_ before: String) -> TypoFix? {
        TypoFix.find(in: before, isTypo: misspelled.contains, guesses: { self.corrections[$0] ?? [] })
    }

    func testFixesTheWordAtTheCaret() {
        XCTAssertEqual(fix("I will recieve"), TypoFix(typo: "recieve", trailing: "", replacement: "receive"))
    }

    func testFixesTheWordJustFinishedWithASpace() {
        let f = fix("that is definately ")
        XCTAssertEqual(f, TypoFix(typo: "definately", trailing: " ", replacement: "definitely"))
        XCTAssertEqual(f?.deleteCount, 11)
        XCTAssertEqual(f?.typed, "definitely ")
    }

    func testLeavesCorrectWordsShortWordsAndNamesAlone() {
        XCTAssertNil(fix("I will receive"))
        XCTAssertEqual(fix("so teh")?.replacement, "the")   // three letters is enough
        XCTAssertNil(fix("Hi Priya"))
        XCTAssertNil(fix("ok "))
        XCTAssertNil(fix("that was wierd  "))     // two spaces: the word is long finished
    }

    func testNeedsACorrection() {
        XCTAssertNil(TypoFix.find(in: "zxqv", isTypo: { _ in true }, guesses: { _ in [] }))
        XCTAssertNil(TypoFix.find(in: "zxqv", isTypo: { _ in true }, guesses: { _ in ["zx qv"] }))
    }
}
