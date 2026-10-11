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
}
