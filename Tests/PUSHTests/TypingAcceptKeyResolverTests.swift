import XCTest
@testable import PUSHCore

final class TypingAcceptKeyResolverTests: XCTestCase {
    // Unshifted characters per key code, as UCKeyTranslate reports them.
    private let us: [Int64: String] = [50: "`", 10: "", 12: "q", 48: "\t"]
    private let ukISO: [Int64: String] = [10: "§", 50: "`", 12: "q"]
    private let german: [Int64: String] = [10: "^", 50: "<", 24: "´", 12: "q"]

    func testWholeSuggestionKeyIsTheOneThatTypesABacktick() {
        XCTAssertEqual(AcceptKeyResolver.wholeSuggestionKey(layout: us), .init(keyCode: 50, option: false))
        XCTAssertEqual(AcceptKeyResolver.wholeSuggestionKey(layout: ukISO), .init(keyCode: 50, option: false))
    }

    func testFallsBackToTheKeyAboveTabWhenNoKeyTypesABacktick() {
        XCTAssertEqual(AcceptKeyResolver.wholeSuggestionKey(layout: german), .init(keyCode: 10, option: false))
    }

    func testOptionTabAsksForAPlainTab() {
        XCTAssertTrue(AcceptKeyResolver.isPlainTabRequest(keyCode: 48, option: true, otherModifiers: false))
        XCTAssertFalse(AcceptKeyResolver.isPlainTabRequest(keyCode: 48, option: false, otherModifiers: false))
        XCTAssertFalse(AcceptKeyResolver.isPlainTabRequest(keyCode: 48, option: true, otherModifiers: true))
    }

    func testNextWordKeyIsTabExceptInTerminals() {
        XCTAssertEqual(AcceptKeyResolver.nextWordKey(surface: .chat), .init(keyCode: 48, option: false))
        XCTAssertEqual(AcceptKeyResolver.nextWordKey(surface: .terminal), .init(keyCode: 124, option: false))
    }

    func testMatching() {
        let tab = AcceptKeyResolver.Key(keyCode: 48, option: false)
        XCTAssertTrue(tab.matches(keyCode: 48, option: false, otherModifiers: false))
        XCTAssertFalse(tab.matches(keyCode: 48, option: true, otherModifiers: false))
        XCTAssertFalse(tab.matches(keyCode: 48, option: false, otherModifiers: true))   // ⇧Tab, ⌘Tab pass through
    }
}
