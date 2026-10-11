import XCTest
import PUSHCore
import CryptoKit

final class TypingHistoryTests: XCTestCase {
    // MARK: Scrubber

    func testScrubsSecretsAndKeepsProse() {
        let text = "Here is the key sk-abcdefghijklmnop1234 and my card 4111 1111 1111 1111, call 416-555-0199."
        let scrubbed = TypingHistoryScrubber.scrub(text)
        XCTAssertFalse(scrubbed.contains("sk-abc"))
        XCTAssertFalse(scrubbed.contains("4111"))
        XCTAssertTrue(scrubbed.contains("416-555-0199"), "phone numbers are not card numbers")
        XCTAssertTrue(scrubbed.hasPrefix("Here is the key [redacted]"))
    }

    func testScrubsLongTokensButNotLongWords() {
        XCTAssertEqual(TypingHistoryScrubber.scrub("token eyJhbGciOiJIUzI1NiJ9abcdefgh end"), "token [redacted] end")
        XCTAssertEqual(TypingHistoryScrubber.scrub("antidisestablishmentarianism"), "antidisestablishmentarianism")
        XCTAssertEqual(TypingHistoryScrubber.scrub("-----BEGIN RSA PRIVATE KEY-----\nMIIabc\n-----END RSA PRIVATE KEY-----"),
                       "[redacted]")
    }

    func testKeepsTheTailOfAHugeRecord() {
        let huge = String(repeating: "word ", count: 5_000) + "the end"
        let scrubbed = TypingHistoryScrubber.scrub(huge)
        XCTAssertEqual(scrubbed.count, TypingHistoryScrubber.maximumCharacters)
        XCTAssertTrue(scrubbed.hasSuffix("the end"))
    }

    // MARK: Index

    private let records = [
        TypingHistoryRecord(text: "Thanks for the brief. The logo concepts for Northwind are almost done; I’ll send the mood board and typography options on Friday.", bundleID: "com.apple.mail"),
        TypingHistoryRecord(text: "Groceries: oat milk, bananas, sourdough bread, coffee beans and dish soap for the weekend.", bundleID: "com.apple.Notes"),
        TypingHistoryRecord(text: "The printer needs the final artwork files by Thursday morning, CMYK with bleed, otherwise the posters slip a week.", bundleID: "com.apple.mail"),
    ]

    func testFindsThePassageOnTheSameTopic() {
        let index = TypingHistoryIndex(records: records)
        let examples = index.examples(query: "Hi Dana, quick update on the Northwind logo concepts and typography",
                                      bundleID: "com.apple.mail", currentText: "")
        XCTAssertEqual(examples.first?.contains("Northwind"), true)
        XCTAssertFalse(examples.contains { $0.contains("Groceries") })
    }

    func testNothingWhenNothingIsRelated() {
        let index = TypingHistoryIndex(records: records)
        XCTAssertEqual(index.examples(query: "the quarterly tax return deadline", bundleID: nil, currentText: ""), [])
        XCTAssertEqual(index.examples(query: "", bundleID: nil, currentText: ""), [])
    }

    func testNeverTheUsersOwnDraft() {
        let index = TypingHistoryIndex(records: records)
        let draft = records[2].text + " Can you confirm"
        let examples = index.examples(query: "printer final artwork files Thursday posters", bundleID: nil, currentText: draft)
        XCTAssertFalse(examples.contains { $0.contains("printer") })
    }

    func testStaysWithinTheBudget() {
        let long = (1...40).map { "Sentence \($0) about the Northwind logo concepts." }.joined(separator: " ")
        // Plenty of other writing, so the topic's words are telling.
        let other = (1...40).map { TypingHistoryRecord(text: "Note \($0): pick up laundry, water plants, book dentist visit.", bundleID: "b") }
        let index = TypingHistoryIndex(records: other + [TypingHistoryRecord(text: long, bundleID: "a")])
        let examples = index.examples(query: "Northwind logo concepts", bundleID: "a", currentText: "", maxCharacters: 400)
        XCTAssertLessThanOrEqual(examples.map(\.count).reduce(0, +), 400)
        XCTAssertFalse(examples.isEmpty)
    }

    // MARK: Query

    func testQueryMovesInBlocksOfEightWords() {
        XCTAssertEqual(TypingHistoryQuery.stableText("one two three"), "")
        let eight = "a b c d e f g h"
        XCTAssertEqual(TypingHistoryQuery.stableText(eight + " i j"), eight)
        XCTAssertEqual(TypingHistoryQuery.stableText(eight + " i j k"), TypingHistoryQuery.stableText(eight + " i"))
    }
}

final class TypingHistoryStorageTests: XCTestCase {
    func testSealedHistoryOpensOnlyWithItsKey() throws {
        let key = SymmetricKey(size: .bits256)
        let records = [TypingHistoryRecord(text: "Hello there, the posters are ready.", bundleID: "com.apple.mail",
                                           date: Date(timeIntervalSince1970: 1_000))]
        let sealed = try TypingHistoryCodec.seal(records, key: key)
        XCTAssertNil(String(data: sealed, encoding: .utf8)?.range(of: "posters"))
        XCTAssertEqual(try TypingHistoryCodec.open(sealed, key: key), records)
        XCTAssertThrowsError(try TypingHistoryCodec.open(sealed, key: SymmetricKey(size: .bits256)))
    }

    func testSameWriting() {
        let draft = "Hi Dana, thanks for the brief. I had a look and"
        XCTAssertTrue(TypingHistoryContinuity.isSameWriting(old: draft, new: draft + " it looks great"))
        XCTAssertTrue(TypingHistoryContinuity.isSameWriting(old: draft, new: "Hi Dana, thanks for the notes. I had a look and"))
        XCTAssertFalse(TypingHistoryContinuity.isSameWriting(old: draft, new: "Are we still on for lunch tomorrow?"))
        // A long note's window moved forward: the old ending is still in it.
        let window = (1...60).map { "Line \($0) of the note." }.joined(separator: " ")
        XCTAssertTrue(TypingHistoryContinuity.isSameWriting(old: window, new: String(window.dropFirst(512)) + " And then"))
    }
}
