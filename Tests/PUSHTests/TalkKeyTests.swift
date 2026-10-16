import XCTest
import CoreGraphics
@testable import PUSH
@testable import PUSHCore

/// The Talk key (a single held modifier) and TYPE's offered accept keys.
final class TalkKeyTests: XCTestCase {

    private func flags(_ generic: CGEventFlags, side: UInt64 = 0) -> CGEventFlags {
        CGEventFlags(rawValue: generic.rawValue | side)
    }

    func testEachKeyIsDownOnlyWithItsOwnSide() {
        XCTAssertTrue(AppState.Hotkey.rightOption.isDown(in: flags(.maskAlternate, side: 0x40)))
        XCTAssertFalse(AppState.Hotkey.rightOption.isDown(in: flags(.maskAlternate, side: 0x20)))
        XCTAssertTrue(AppState.Hotkey.leftShift.isDown(in: flags(.maskShift, side: 0x02)))
        XCTAssertFalse(AppState.Hotkey.leftShift.isDown(in: flags(.maskShift, side: 0x04)))
        XCTAssertTrue(AppState.Hotkey.rightShift.isDown(in: flags(.maskShift, side: 0x04)))
        XCTAssertFalse(AppState.Hotkey.rightControl.isDown(in: flags(.maskCommand, side: 0x2000)))
    }

    func testFnHasNoSide() {
        XCTAssertTrue(AppState.Hotkey.fn.isDown(in: flags(.maskSecondaryFn)))
        XCTAssertFalse(AppState.Hotkey.fn.isDown(in: flags(.maskShift, side: 0x02)))
    }

    func testOnlyTypingModifiersWaitBeforeStarting() {
        XCTAssertEqual(AppState.Hotkey.allCases.filter(\.startsAfterHold), [.rightShift, .leftShift, .fn])
    }

    func testTheOriginalSixStillLoad() {
        for raw in ["rightOption", "leftOption", "rightCommand", "leftCommand", "rightControl", "leftControl"] {
            XCTAssertNotNil(AppState.Hotkey(rawValue: raw), raw)
        }
    }

    func testNamesAreSpelledOut() {
        XCTAssertEqual(AppState.Hotkey.rightOption.displayName, "Right Option")
        XCTAssertEqual(AppState.Hotkey.fn.displayName, "Fn (Globe)")
    }

    // MARK: - TYPE's accept keys

    func testTheOfferedTypeKeysAreSingleKeysWithTheDefaultsFirst() {
        let us: [Int64: String] = [50: "`", 0: "a"]
        XCTAssertEqual(AcceptKeyResolver.choices(layout: us).map(\.keyCode), [48, 50, 124, 119])
        XCTAssertTrue(AcceptKeyResolver.choices(layout: us).allSatisfy { !$0.option })
    }

    func testAnOlderRecordedKeyIsNotOffered() {
        XCTAssertTrue(AcceptKeyResolver.isOffered(.init(keyCode: 48, option: false)))
        XCTAssertTrue(AcceptKeyResolver.isOffered(.init(keyCode: 10, option: false)))
        XCTAssertFalse(AcceptKeyResolver.isOffered(.init(keyCode: 124, option: true)))
        XCTAssertFalse(AcceptKeyResolver.isOffered(.init(keyCode: 96, option: false)))   // F5
    }
}
