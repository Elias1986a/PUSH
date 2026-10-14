import XCTest
import CryptoKit
import PUSHCore

final class TypingHistorySyncTests: XCTestCase {
    private func record(_ text: String, app: String = "com.apple.mail", at seconds: TimeInterval) -> TypingHistoryRecord {
        TypingHistoryRecord(text: text, bundleID: app, windowTitle: "Re: plan", date: Date(timeIntervalSince1970: seconds))
    }

    func testMergeIsTheUnionOldestFirst() {
        let a = TypingHistorySnapshot(records: [record("First thing I wrote about the plan today", at: 200)])
        let b = TypingHistorySnapshot(records: [record("An older note about something else entirely", at: 100)])
        let merged = TypingHistorySync.merge(a, b)
        XCTAssertEqual(merged.records.map(\.date.timeIntervalSince1970), [100, 200])
    }

    func testTheSameWritingOnBothMacsIsKeptOnce() {
        let r = record("Thanks for sending the contract over, I will review it tonight", at: 100)
        let merged = TypingHistorySync.merge(TypingHistorySnapshot(records: [r]), TypingHistorySnapshot(records: [r]))
        XCTAssertEqual(merged.records.count, 1)
    }

    /// One Mac kept the note when it was short, the other after it grew.
    func testAShorterEarlierCopyGivesWayToTheLongerOne() {
        let short = record("Thanks for sending the contract over. I", at: 100)
        let long = record("Thanks for sending the contract over. I will review it tonight and get back to you.", at: 200)
        let merged = TypingHistorySync.merge(TypingHistorySnapshot(records: [short]), TypingHistorySnapshot(records: [long]))
        XCTAssertEqual(merged.records.map(\.text), [long.text])
    }

    func testDifferentAppsAreNotMerged() {
        let a = record("Thanks for sending the contract over, I will review it", app: "com.apple.mail", at: 100)
        let b = record("Thanks for sending the contract over, I will review it", app: "com.tinyspeck.slackmacgap", at: 100)
        XCTAssertEqual(TypingHistorySync.merge(TypingHistorySnapshot(records: [a]), TypingHistorySnapshot(records: [b])).records.count, 2)
    }

    /// Delete All on one Mac reaches the other: what it still holds from before is dropped,
    /// and a newer note survives.
    func testDeleteAllRemovesOlderWritingEverywhere() {
        let old = record("Something I wrote before pressing Delete All on the other Mac", at: 100)
        let new = record("Something written after it, which is still wanted here", at: 300)
        let cleared = TypingHistorySnapshot(clearedAt: Date(timeIntervalSince1970: 200), records: [])
        let merged = TypingHistorySync.merge(TypingHistorySnapshot(records: [old, new]), cleared)
        XCTAssertEqual(merged.records.map(\.text), [new.text])
        XCTAssertEqual(merged.clearedAt, Date(timeIntervalSince1970: 200))
    }

    func testOnlyTheNewestRecordsAreKept() {
        let many = (0..<(TypingHistorySync.maximumRecords + 20)).map { record("Note number \($0) about the plan and how it goes", at: TimeInterval($0)) }
        let merged = TypingHistorySync.merge(TypingHistorySnapshot(records: many), TypingHistorySnapshot())
        XCTAssertEqual(merged.records.count, TypingHistorySync.maximumRecords)
        XCTAssertEqual(merged.records.first?.date.timeIntervalSince1970, 20)
    }

    // MARK: - Pack

    func testPackAndUnpackRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let snapshot = TypingHistorySnapshot(clearedAt: Date(timeIntervalSince1970: 50),
                                             records: [record("Thanks for sending the contract over, I will review it", at: 100)])
        let chunks = try TypingHistorySync.pack(snapshot, key: key)
        XCTAssertEqual(try TypingHistorySync.unpack(chunks, key: key), snapshot)
    }

    func testAnotherKeyCannotOpenIt() throws {
        let chunks = try TypingHistorySync.pack(TypingHistorySnapshot(records: [record("A note long enough to be kept here", at: 1)]),
                                                key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try TypingHistorySync.unpack(chunks, key: SymmetricKey(size: .bits256)))
    }

    /// iCloud's key-value store holds 1 MB in all: a long history is trimmed
    /// from the old end until it fits, and no chunk is bigger than a value allows.
    func testALongHistoryIsTrimmedOldestFirstToFitTheBudget() throws {
        let key = SymmetricKey(size: .bits256)
        var rng = SystemRandomNumberGenerator()
        // Incompressible-ish text, so the size is real.
        func noise() -> String { String((0..<1_500).map { _ in "abcdefghijklmnopqrstuvwxyz ".randomElement(using: &rng)! }) }
        let records = (0..<600).map { record(noise(), at: TimeInterval($0)) }
        let budget = 120_000
        let chunks = try TypingHistorySync.pack(TypingHistorySnapshot(records: records), key: key, budget: budget)
        XCTAssertLessThanOrEqual(chunks.reduce(0) { $0 + $1.count }, budget)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= TypingHistorySync.chunkBytes })
        let back = try TypingHistorySync.unpack(chunks, key: key)
        XCTAssertLessThan(back.records.count, records.count)
        // What is left is the newest.
        XCTAssertEqual(back.records.last?.date.timeIntervalSince1970, 599)
    }
}
