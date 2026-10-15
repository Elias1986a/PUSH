import XCTest
@testable import PUSH

/// How long a licensed Mac keeps working without reaching Polar (30 days).
final class LicenseOfflineAllowanceTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func testARecentCheckIsFine() {
        XCTAssertFalse(LicenseModel.isOverdue(lastValidated: now.addingTimeInterval(-29 * day), now: now))
    }

    func testThirtyDaysWithoutACheckIsOverdue() {
        XCTAssertTrue(LicenseModel.isOverdue(lastValidated: now.addingTimeInterval(-30 * day), now: now))
    }

    /// No real check is dated in the future; a record that says so was edited
    /// to skip every check, so it is checked at once.
    func testACheckDatedInTheFutureIsOverdue() {
        XCTAssertTrue(LicenseModel.isOverdue(lastValidated: now.addingTimeInterval(day), now: now))
    }
}
