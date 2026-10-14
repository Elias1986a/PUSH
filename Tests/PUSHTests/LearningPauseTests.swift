import XCTest
import PUSHCore

final class LearningPauseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testKeepsWhenNotPaused() {
        var pause = LearningPause()
        XCTAssertTrue(pause.mayKeep(element: 1, at: now))
    }

    func testNothingIsKeptWhilePaused() {
        var pause = LearningPause(until: now.addingTimeInterval(60))
        XCTAssertTrue(pause.isPaused(at: now))
        XCTAssertFalse(pause.mayKeep(element: 1, at: now))
    }

    /// The field typed in during the pause stays out after it ends, or its
    /// whole text (the paused part too) would be kept on the next key.
    func testAFieldWrittenWhilePausedStaysOutAfterwards() {
        var pause = LearningPause(until: now.addingTimeInterval(60))
        _ = pause.mayKeep(element: 7, at: now)
        let later = now.addingTimeInterval(120)
        XCTAssertFalse(pause.isPaused(at: later))
        XCTAssertFalse(pause.mayKeep(element: 7, at: later))
        XCTAssertTrue(pause.mayKeep(element: 8, at: later))
    }

    func testAPastPauseIsNotAPause() {
        XCTAssertFalse(LearningPause(until: now.addingTimeInterval(-1)).isPaused(at: now))
    }

    func testOnlyTheLatestFieldsAreRemembered() {
        var pause = LearningPause(until: now.addingTimeInterval(60))
        for e in 0..<(LearningPause.remembered + 5) { _ = pause.mayKeep(element: e, at: now) }
        XCTAssertEqual(pause.skipped.count, LearningPause.remembered)
    }
}
