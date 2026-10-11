import XCTest
@testable import PUSH

/// The drag-to-grant card's placement and show/hide rules. Both are pure so the
/// awkward parts — Core Graphics' top-left origin against AppKit's bottom-left,
/// a second display above or beside the main one, and a card that must not
/// flicker as focus moves between System Settings and its auth sheet — are
/// pinned without a window server.
final class PermissionGuideTests: XCTestCase {

    // Main display 1512×982 at the origin; an external 2560×1440 to its right,
    // raised so its top sits 300pt above the main display's top.
    private let mainScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let externalScreen = CGRect(x: 1512, y: -158, width: 2560, height: 1440)

    // MARK: - Coordinate conversion

    func testCoreGraphicsRectOnMainDisplayFlipsToAppKit() {
        // 100pt below the top of a 982pt display, 500pt tall.
        let cg = CGRect(x: 200, y: 100, width: 700, height: 500)
        let appKit = PermissionGuideGeometry.appKitRect(fromCG: cg, primaryScreenHeight: 982)
        XCTAssertEqual(appKit, CGRect(x: 200, y: 382, width: 700, height: 500))
    }

    func testCoreGraphicsRectAboveTheMainDisplayGoesAboveIt() {
        // An external display raised above the main one has negative CG y.
        let cg = CGRect(x: 1600, y: -250, width: 700, height: 500)
        let appKit = PermissionGuideGeometry.appKitRect(fromCG: cg, primaryScreenHeight: 982)
        XCTAssertEqual(appKit, CGRect(x: 1600, y: 732, width: 700, height: 500))
    }

    // MARK: - Which screen

    func testScreenIsTheOneHoldingMostOfTheWindow() {
        let screens = [mainScreen, externalScreen]
        let onMain = CGRect(x: 100, y: 100, width: 600, height: 400)
        let mostlyExternal = CGRect(x: 1400, y: 100, width: 600, height: 400)
        XCTAssertEqual(PermissionGuideGeometry.screenIndex(for: onMain, screenFrames: screens), 0)
        XCTAssertEqual(PermissionGuideGeometry.screenIndex(for: mostlyExternal, screenFrames: screens), 1)
    }

    func testNoScreenWhenTheWindowIsOffEveryDisplay() {
        let nowhere = CGRect(x: -5000, y: -5000, width: 100, height: 100)
        XCTAssertNil(PermissionGuideGeometry.screenIndex(for: nowhere, screenFrames: [mainScreen]))
    }

    // MARK: - Card placement

    func testCardSitsNearTheBottomOfTheWindowCentredOnTheContentArea() {
        let settings = CGRect(x: 100, y: 100, width: 740, height: 700)
        let card = CGSize(width: 480, height: 104)
        let origin = PermissionGuideGeometry.cardOrigin(
            settingsFrame: settings, visibleFrame: mainScreen, cardSize: card)
        // Content area = right of the 220pt sidebar: x 320…840, centre 580.
        XCTAssertEqual(origin.x, 580 - 240)
        XCTAssertEqual(origin.y, 100 + PermissionGuideGeometry.bottomInset)
    }

    func testCardIsClampedOntoTheScreen() {
        // Window hanging off the bottom-right corner of the display.
        let settings = CGRect(x: 1300, y: -300, width: 740, height: 700)
        let card = CGSize(width: 480, height: 104)
        let origin = PermissionGuideGeometry.cardOrigin(
            settingsFrame: settings, visibleFrame: mainScreen, cardSize: card)
        XCTAssertEqual(origin.x, 1512 - 480 - 8)
        XCTAssertEqual(origin.y, 8)
    }

    func testNarrowWindowKeepsTheCardInsideIt() {
        // Content area narrower than the card: the card starts at the window's
        // left edge plus the margin rather than poking out past it.
        let settings = CGRect(x: 100, y: 100, width: 600, height: 600)
        let card = CGSize(width: 480, height: 104)
        let origin = PermissionGuideGeometry.cardOrigin(
            settingsFrame: settings, visibleFrame: mainScreen, cardSize: card)
        XCTAssertEqual(origin.x, 100 + 600 - 480 - 8)
    }

    // MARK: - Show / hide

    typealias Action = PermissionGuideTracker.Action
    private let frame = CGRect(x: 10, y: 10, width: 700, height: 500)

    func testFirstSightingPresents() {
        XCTAssertEqual(PermissionGuideTracker.action(settingsFrame: frame, isVisible: false, lastFrame: nil), .present)
    }

    func testSameFrameDoesNothing() {
        XCTAssertEqual(PermissionGuideTracker.action(settingsFrame: frame, isVisible: true, lastFrame: frame), .none)
    }

    func testMovedWindowRepositions() {
        let moved = frame.offsetBy(dx: 40, dy: 0)
        XCTAssertEqual(PermissionGuideTracker.action(settingsFrame: moved, isVisible: true, lastFrame: frame), .move)
    }

    func testSettingsLeavingTheFrontHides() {
        XCTAssertEqual(PermissionGuideTracker.action(settingsFrame: nil, isVisible: true, lastFrame: frame), .hide)
    }

    func testStillGoneDoesNothing() {
        XCTAssertEqual(PermissionGuideTracker.action(settingsFrame: nil, isVisible: false, lastFrame: frame), .none)
    }

    func testComingBackPresentsAgain() {
        XCTAssertEqual(PermissionGuideTracker.action(settingsFrame: frame, isVisible: false, lastFrame: frame), .present)
    }
}
