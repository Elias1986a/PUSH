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

    func testAChosenNextWordKeyIsUsedEverywhere() {
        let backslash = AcceptKeyResolver.Key(keyCode: 42, option: false)
        XCTAssertEqual(AcceptKeyResolver.nextWordKey(surface: .chat, chosen: backslash), backslash)
        XCTAssertEqual(AcceptKeyResolver.nextWordKey(surface: .terminal, chosen: backslash), backslash)
    }

    func testKeysSaveAndLoad() {
        let key = AcceptKeyResolver.Key(keyCode: 124, option: true)
        XCTAssertEqual(key.stored, "124+opt")
        XCTAssertEqual(AcceptKeyResolver.Key(stored: "124+opt"), key)
        XCTAssertEqual(AcceptKeyResolver.Key(stored: "48"), .init(keyCode: 48, option: false))
        XCTAssertNil(AcceptKeyResolver.Key(stored: "tab"))
    }

    func testKeysNeededForWritingAreRefused() {
        func refused(_ code: Int64, option: Bool = false, _ character: String? = nil) -> Bool {
            AcceptKeyResolver.refusal(.init(keyCode: code, option: option), character: character) != nil
        }
        XCTAssertTrue(refused(53))                          // Esc
        XCTAssertTrue(refused(36))                          // Return
        XCTAssertTrue(refused(51))                          // Delete
        XCTAssertTrue(refused(49, " "))                     // Space
        XCTAssertTrue(refused(48, option: true))            // ⌥Tab
        XCTAssertTrue(refused(0, "a"))                      // a letter
        XCTAssertTrue(refused(18, "1"))                     // a number
        XCTAssertFalse(refused(0, option: true, "a"))       // ⌥A is fine
        XCTAssertFalse(refused(48, "\t"))                   // Tab
        XCTAssertFalse(refused(50, "`"))                    // the ~ key
        XCTAssertFalse(refused(124))                        // →
    }

    func testNames() {
        let layout: [Int64: String] = [50: "`", 42: "\\", 48: "\t"]
        XCTAssertEqual(AcceptKeyResolver.name(of: .init(keyCode: 48, option: false), layout: layout), "Tab")
        XCTAssertEqual(AcceptKeyResolver.name(of: .init(keyCode: 50, option: false), layout: layout), "` ~")
        XCTAssertEqual(AcceptKeyResolver.name(of: .init(keyCode: 124, option: true), layout: layout), "⌥→")
        XCTAssertEqual(AcceptKeyResolver.name(of: .init(keyCode: 42, option: false), layout: layout), "\\")
    }
}
