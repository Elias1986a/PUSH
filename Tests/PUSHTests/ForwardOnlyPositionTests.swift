import XCTest
@testable import PUSHCore

/// The scroll must never rewind on its own. Prediction runs ahead of the last
/// confirmed match, and when it is withdrawn — the moment tracking lapses — the
/// target drops by however far it had run. Following that makes the text fall
/// back, which is unreadable.
final class ForwardOnlyPositionTests: XCTestCase {

    func testForwardMovesAreFollowed() {
        var position = ForwardOnlyPosition()
        XCTAssertEqual(position.advance(to: 1.0), 1.0)
        XCTAssertEqual(position.advance(to: 1.4), 1.4)
        XCTAssertEqual(position.advance(to: 2.2), 2.2)
    }

    func testBackwardTargetsNeverMoveIt() {
        var position = ForwardOnlyPosition()
        position.advance(to: 3.0)

        // Small: the shape of prediction overshooting a partial.
        XCTAssertEqual(position.advance(to: 2.7), 3.0)
        // Large: the shape of prediction being withdrawn at adrift. This is the
        // one that got through a tolerance and rewound the text a line and a
        // half.
        XCTAssertEqual(position.advance(to: 1.0), 3.0)
        // ...and it resumes as soon as the target passes where it held.
        XCTAssertEqual(position.advance(to: 3.1), 3.1)
    }

    func testResetIsTheOnlyWayBack() {
        var position = ForwardOnlyPosition()
        position.advance(to: 9.0)
        // An arrow key, or a new take. Not matching.
        position.reset(to: 1.0)
        XCTAssertEqual(position.value, 1.0)
        XCTAssertEqual(position.advance(to: 1.2), 1.2)
    }
}
