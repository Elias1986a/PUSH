import XCTest
@testable import PUSHCore

/// The scroll must not bounce. Prediction overshoots and the next partial
/// lands behind it; following that literally rises and falls once per partial.
final class ForwardOnlyPositionTests: XCTestCase {

    func testForwardMovesAreFollowed() {
        var position = ForwardOnlyPosition()
        XCTAssertEqual(position.advance(to: 1.0), 1.0)
        XCTAssertEqual(position.advance(to: 1.4), 1.4)
        XCTAssertEqual(position.advance(to: 2.2), 2.2)
    }

    func testSmallBackwardCorrectionsHoldRatherThanRewind() {
        var position = ForwardOnlyPosition(tolerance: 0.75)
        position.advance(to: 3.0)

        // The shape of a prediction overshoot: ran ahead, truth landed behind.
        XCTAssertEqual(position.advance(to: 2.7), 3.0)
        XCTAssertEqual(position.advance(to: 2.4), 3.0)
        // ...and resumes as soon as the target passes where it held.
        XCTAssertEqual(position.advance(to: 3.1), 3.1)
    }

    func testALargeBackwardJumpIsBelieved() {
        var position = ForwardOnlyPosition(tolerance: 0.75)
        position.advance(to: 5.0)

        // A reader going back to re-read, not jitter.
        XCTAssertEqual(position.advance(to: 3.0), 3.0)
    }

    func testTheBoundaryIsTheTolerance() {
        var position = ForwardOnlyPosition(tolerance: 0.75)
        position.advance(to: 4.0)
        // Just inside: held.
        XCTAssertEqual(position.advance(to: 3.30), 4.0)

        var other = ForwardOnlyPosition(tolerance: 0.75)
        other.advance(to: 4.0)
        // Just outside: followed.
        XCTAssertEqual(other.advance(to: 3.20), 3.20)
    }

    func testResetIgnoresTheRatchet() {
        var position = ForwardOnlyPosition()
        position.advance(to: 9.0)
        // An explicit correction is the one thing that always wins.
        position.reset(to: 1.0)
        XCTAssertEqual(position.value, 1.0)
        XCTAssertEqual(position.advance(to: 1.2), 1.2)
    }
}
