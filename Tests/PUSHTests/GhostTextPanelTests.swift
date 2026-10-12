import AppKit
import XCTest
@testable import PUSH

@MainActor
final class GhostTextPanelTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 14)

    /// After accepting "the", " weekend?" wrapped to the next line and Tab
    /// typed "weekend?" — "theweekend?" in Notes.
    func testWrappedTextKeepsItsSpaceForAccepting() throws {
        let result = try XCTUnwrap(GhostTextPanel.wrapped(" weekend?", width: 500, font: font))
        XCTAssertEqual(result.drawn, "weekend?")
        XCTAssertEqual(result.accepted, " weekend?")
    }

    func testWrappedTextFitsWholeWords() throws {
        let narrow = GhostTextPanel.width(of: "weekend with", caretHeight: 18)
        let result = try XCTUnwrap(GhostTextPanel.wrapped(" weekend with the family",
                                                          width: narrow + 1, font: GhostTextPanel.font(forCaret: 18)))
        XCTAssertEqual(result.accepted, " weekend with")
        XCTAssertEqual(result.drawn, "weekend with")
    }

    func testNothingFits() {
        XCTAssertNil(GhostTextPanel.wrapped(" weekend?", width: 2, font: font))
    }

    func testTheFieldsFontIsUsedAtItsOwnSize() {
        // TextEdit: Helvetica 12 with a 14-point caret (the caret alone gave 10.9).
        let font = GhostTextPanel.font(forCaret: 14, field: FieldFont(name: "Helvetica", size: 12))
        XCTAssertEqual(font.fontName, "Helvetica")
        XCTAssertEqual(font.pointSize, 12)
    }

    func testAZoomedViewKeepsTheFaceButTakesTheCaretsSize() {
        // A page at 200%: 16 reported, a 40-point caret.
        let font = GhostTextPanel.font(forCaret: 40, field: FieldFont(name: "Helvetica", size: 16))
        XCTAssertEqual(font.fontName, "Helvetica")
        XCTAssertEqual(font.pointSize, 31.2, accuracy: 0.01)
    }

    func testAnUnknownFaceFallsBackToTheSystemFontAtTheReportedSize() {
        let font = GhostTextPanel.font(forCaret: 18, field: FieldFont(name: "NoSuchFont-Web", size: 15))
        XCTAssertEqual(font.pointSize, 15)
        XCTAssertEqual(font.familyName, NSFont.systemFont(ofSize: 15).familyName)
    }
}
