import XCTest
@testable import PUSH

@MainActor
final class TypingPlacementTests: XCTestCase {
    private let caret = CGRect(x: 100, y: 500, width: 0, height: 16)
    private let field = CGRect(x: 80, y: 400, width: 400, height: 120)

    func testInlineWhenNothingFollowsOnTheLine() {
        XCTAssertEqual(TypingPlacement.decide(caretRect: caret, after: "", fieldFrame: field), .inline(caret: caret, field: field))
        XCTAssertEqual(TypingPlacement.decide(caretRect: caret, after: nil, fieldFrame: field), .inline(caret: caret, field: field))
        XCTAssertEqual(TypingPlacement.decide(caretRect: caret, after: "  \nnext line", fieldFrame: field), .inline(caret: caret, field: field))
    }

    func testCardUnderTheCaretWhenTextFollowsOnTheSameLine() {
        XCTAssertEqual(TypingPlacement.decide(caretRect: caret, after: " and more", fieldFrame: field), .card(below: caret))
    }

    func testCardUnderTheFieldWithoutACaret() {
        XCTAssertEqual(TypingPlacement.decide(caretRect: nil, after: nil, fieldFrame: field), .card(below: field))
    }

    func testTallFieldWithoutACaretGetsTheCardInsideItsTopLeft() {
        let body = CGRect(x: 80, y: 100, width: 600, height: 500)
        XCTAssertEqual(TypingPlacement.decide(caretRect: nil, after: nil, fieldFrame: body),
                       .card(below: CGRect(x: 88, y: 560, width: 0, height: 0)))
    }

    func testCardUnderTheCaretWithoutAField() {
        XCTAssertEqual(TypingPlacement.decide(caretRect: caret, after: "x", fieldFrame: nil), .card(below: caret))
    }

    func testNothingWhenNeitherIsKnown() {
        XCTAssertNil(TypingPlacement.decide(caretRect: nil, after: nil, fieldFrame: nil))
    }

    func testExcludedApps() {
        XCTAssertTrue(TypingExclusions.isExcluded(bundleID: "com.1password.1password"))
        XCTAssertTrue(TypingExclusions.isExcluded(bundleID: "com.apple.keychainaccess"))
        XCTAssertTrue(TypingExclusions.isExcluded(bundleID: "com.apple.systempreferences"))
        XCTAssertTrue(TypingExclusions.isExcluded(bundleID: "com.push.voicetotext"))
        XCTAssertFalse(TypingExclusions.isExcluded(bundleID: "com.apple.Notes"))
        XCTAssertFalse(TypingExclusions.isExcluded(bundleID: nil))
    }
}

@MainActor
final class GhostTextFittingTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 13)

    func testWholeTextWhenItFits() {
        XCTAssertEqual(GhostTextPanel.fitting(" to ask you", width: 500, font: font), " to ask you")
    }

    func testWholeWordsOnlyWhenItDoesNot() {
        let full = " to ask you about the following question"
        let cut = GhostTextPanel.fitting(full, width: GhostTextPanel.width(of: " to ask you", caretHeight: 16.7) + 2, font: font)
        XCTAssertEqual(cut, " to ask you")
    }

    func testNilWhenNotEvenOneWordFits() {
        XCTAssertNil(GhostTextPanel.fitting(" university", width: 5, font: font))
        XCTAssertNil(GhostTextPanel.fitting(" a", width: 0, font: font))
    }
}
