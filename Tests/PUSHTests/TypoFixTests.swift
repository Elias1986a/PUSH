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

    func testKeepsOfferingTheFixWhileTheNextWordIsTyped() {
        let f = fix("I will recieve i")
        XCTAssertEqual(f, TypoFix(typo: "recieve", trailing: " i", replacement: "receive"))
        XCTAssertEqual(f?.deleteCount, 9)
        XCTAssertEqual(f?.typed, "receive i")
        XCTAssertEqual(fix("that was wierd bu")?.typed, "weird bu")
    }

    func testAWordInProgressIsNotATypo() {
        let f = TypoFix.find(in: "really apprec", isTypo: { $0 == "apprec" },
                             isInProgress: { $0 == "apprec" }, guesses: { _ in ["approach"] })
        XCTAssertNil(f)
        // …but the misspelled word before it still gets its fix.
        let g = TypoFix.find(in: "I will recieve apprec", isTypo: { $0 == "recieve" || $0 == "apprec" },
                             isInProgress: { $0 == "apprec" }, guesses: { $0 == "recieve" ? ["receive"] : ["approach"] })
        XCTAssertEqual(g?.typed, "receive apprec")
    }
}
