import XCTest
@testable import PUSH

@MainActor
final class TypeIndicatorTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testSitsLeftOfTheFieldOnTheCaretsLine() {
        let field = CGRect(x: 300, y: 100, width: 600, height: 700)
        let caret = CGRect(x: 420, y: 600, width: 0, height: 18)
        let frame = TypeIndicatorPanel.frame(field: field, caret: caret, screen: screen)
        XCTAssertEqual(frame.maxX, field.minX - 5)
        XCTAssertEqual(frame.midY, caret.midY)
    }

    func testMovesRightWhenTheFieldTouchesTheScreenEdge() {
        let field = CGRect(x: 0, y: 100, width: 600, height: 30)
        let frame = TypeIndicatorPanel.frame(field: field, caret: nil, screen: screen)
        XCTAssertEqual(frame.minX, field.maxX + 5)
        XCTAssertEqual(frame.midY, field.midY)
    }

    func testTallFieldWithoutCaretUsesTheFirstLine() {
        let field = CGRect(x: 300, y: 100, width: 600, height: 700)
        let frame = TypeIndicatorPanel.frame(field: field, caret: nil, screen: screen)
        XCTAssertEqual(frame.maxY, field.maxY - 8)
    }
}
