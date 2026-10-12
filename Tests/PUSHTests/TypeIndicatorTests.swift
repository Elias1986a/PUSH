import XCTest
@testable import PUSH

final class TypeIndicatorTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testFirstLeftOfTheFieldOnTheCaretsLineThenRightAboveBelow() {
        let field = CGRect(x: 300, y: 100, width: 600, height: 300)
        let caret = CGRect(x: 420, y: 300, width: 0, height: 18)
        let spots = TypeIndicatorPanel.candidates(field: field, caret: caret, screen: screen)
        XCTAssertEqual(spots.count, 4)
        XCTAssertEqual(spots[0].maxX, field.minX - 5)
        XCTAssertEqual(spots[0].midY, caret.midY)
        XCTAssertEqual(spots[1].minX, field.maxX + 5)
        XCTAssertEqual(spots[2].minY, field.maxY + 5)        // above (AppKit: y grows upward)
        XCTAssertEqual(spots[3].maxY, field.minY - 5)        // below
    }

    func testSpotsOffScreenAreSkipped() {
        let field = CGRect(x: 0, y: 100, width: 600, height: 30)
        let spots = TypeIndicatorPanel.candidates(field: field, caret: nil, screen: screen)
        XCTAssertEqual(spots.first?.minX, field.maxX + 5)    // nothing fits to the left
        XCTAssertEqual(spots.first?.midY, field.midY)
    }

    func testTallFieldWithoutCaretUsesTheFirstLine() {
        let field = CGRect(x: 300, y: 100, width: 600, height: 700)
        let spots = TypeIndicatorPanel.candidates(field: field, caret: nil, screen: screen)
        XCTAssertEqual(spots[0].maxY, field.maxY - 8)
    }
}
