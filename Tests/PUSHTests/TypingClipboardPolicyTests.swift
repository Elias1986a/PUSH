import XCTest
import PUSHCore

final class TypingClipboardPolicyTests: XCTestCase {
    private let now = Date()

    func testAShortFreshCopyIsUsed() {
        XCTAssertEqual(ClipboardPolicy.select("221B Baker Street, London", copiedAt: now.addingTimeInterval(-30), now: now,
                                              before: "Sure, the address is"), "221B Baker Street, London")
    }

    func testAnOldCopyIsNot() {
        XCTAssertNil(ClipboardPolicy.select("221B Baker Street", copiedAt: now.addingTimeInterval(-600), now: now,
                                            before: "Sure, the address is"))
    }

    func testALongCopyNeedsAWordInCommon() {
        let article = String(repeating: "The quarterly numbers for streaming subscriptions grew steadily. ", count: 4)
        XCTAssertNil(ClipboardPolicy.select(article, copiedAt: now, now: now, before: "Hey, are we still on for lunch"))
        let used = ClipboardPolicy.select(article, copiedAt: now, now: now, before: "Quick note on the subscriptions")
        XCTAssertNotNil(used)
        XCTAssertLessThanOrEqual(used!.count, ClipboardPolicy.maximumCharacters + 1)
    }

    func testSecretsAndTheDraftItselfAreNot() {
        XCTAssertNil(ClipboardPolicy.select("sk-abcdefghijklmnop1234", copiedAt: now, now: now, before: "my key is"))
        XCTAssertNil(ClipboardPolicy.select("thanks for sending the brief", copiedAt: now, now: now,
                                            before: "Hi Sam, thanks for sending the brief over"))
    }
}
