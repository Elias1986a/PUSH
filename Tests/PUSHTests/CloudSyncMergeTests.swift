import XCTest
@testable import PUSH

/// Tests for the dictionary merge. Every case here is a way a naive
/// implementation loses or resurrects one of the user's entries.
final class CloudSyncMergeTests: XCTestCase {

    private typealias Correction = CorrectionsStore.Correction

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func entry(
        _ wrong: String,
        _ right: String,
        id: UUID = UUID(),
        at offset: TimeInterval = 0,
        deleted: TimeInterval? = nil
    ) -> Correction {
        Correction(
            id: id,
            wrong: wrong,
            right: right,
            kind: .always,
            entity: nil,
            modifiedAt: t0.addingTimeInterval(deleted ?? offset),
            deletedAt: deleted.map { t0.addingTimeInterval($0) }
        )
    }

    private func merge(
        _ local: [Correction],
        _ remote: [Correction],
        now: TimeInterval = 100
    ) -> (alive: [Correction], tombstones: [Correction]) {
        CloudSync.mergeCorrections(local: local, remote: remote, now: t0.addingTimeInterval(now))
    }

    // MARK: - The core promise: no entry is ever lost

    func testEntriesAddedOnDifferentMachinesBothSurvive() {
        let mine = entry("Hamer", "Hammer")
        let theirs = entry("Parakeet", "Parakeet")

        let result = merge([mine], [theirs])

        XCTAssertEqual(Set(result.alive.map(\.wrong)), ["Hamer", "Parakeet"],
                       "a union must keep both sides; last-writer-wins on the list would drop one")
    }

    func testTheSameEntryEditedTwiceResolvesToTheNewer() {
        let id = UUID()
        let older = entry("Hamer", "Hammer", id: id, at: 10)
        let newer = entry("Hamer", "Hamer", id: id, at: 20)

        XCTAssertEqual(merge([older], [newer]).alive.map(\.right), ["Hamer"])
        XCTAssertEqual(merge([newer], [older]).alive.map(\.right), ["Hamer"],
                       "order of arguments must not change the outcome")
    }

    // MARK: - Deletions

    func testADeletedEntryDoesNotComeBackFromTheOtherMachine() {
        let id = UUID()
        let alive = entry("Hamer", "Hammer", id: id, at: 10)
        let deleted = entry("Hamer", "Hammer", id: id, at: 10, deleted: 20)

        let result = merge([deleted], [alive])

        XCTAssertTrue(result.alive.isEmpty, "union by id without tombstones resurrects deletions")
        XCTAssertEqual(result.tombstones.count, 1, "the deletion has to travel to the other machine")
    }

    func testReAddingAfterADeleteWins() {
        let id = UUID()
        let deleted = entry("Hamer", "Hammer", id: id, at: 10, deleted: 20)
        let reAdded = entry("Hamer", "Hammer", id: id, at: 30)

        let result = merge([deleted], [reAdded])

        XCTAssertEqual(result.alive.count, 1, "a later re-add is deliberate and must survive")
        XCTAssertTrue(result.tombstones.isEmpty)
    }

    func testTombstonesExpire() {
        let old = entry("Gone", "Gone", deleted: 1)
        let recent = entry("Fresh", "Fresh", deleted: 95)

        // 40 days later.
        let result = merge([old, recent], [], now: CloudSync.tombstoneLifetime + 200)

        XCTAssertTrue(result.tombstones.isEmpty || result.tombstones.allSatisfy { $0.wrong != "Gone" },
                      "tombstones must not accumulate forever")
    }

    // MARK: - Independent duplicates

    func testTheSameWordAddedOnBothMachinesCollapsesToOne() {
        // Different UUIDs, identical meaning — what happens when someone adds
        // the same correction on two Macs before they ever sync.
        let mine = entry("Hamer", "Hammer", at: 20)
        let theirs = entry("hamer", "hammer", at: 10)

        let result = merge([mine], [theirs])

        XCTAssertEqual(result.alive.count, 1, "identical corrections must not appear twice")
        XCTAssertEqual(result.alive.first?.modifiedAt, self.t0.addingTimeInterval(10),
                       "the older one is kept so the surviving id is stable")
    }

    func testDifferentKindsAreNotTreatedAsDuplicates() {
        let always = Correction(wrong: "Hamer", right: "Hammer", kind: .always, modifiedAt: t0)
        let contextual = Correction(wrong: "Hamer", right: "Hammer", kind: .contextual, modifiedAt: t0)

        XCTAssertEqual(merge([always], [contextual]).alive.count, 2,
                       "kind is part of the meaning; collapsing them would silently change behaviour")
    }

    // MARK: - Degenerate inputs

    func testEmptySidesAreHandled() {
        let mine = entry("Hamer", "Hammer")
        XCTAssertEqual(merge([mine], []).alive.count, 1)
        XCTAssertEqual(merge([], [mine]).alive.count, 1)
        XCTAssertTrue(merge([], []).alive.isEmpty)
    }

    func testMergeIsIdempotent() {
        let a = entry("Hamer", "Hammer", at: 10)
        let b = entry("Parakeet", "Parakeet", at: 20)
        let deleted = entry("Gone", "Gone", at: 5, deleted: 30)

        let first = merge([a, deleted], [b])
        let second = merge(first.alive + first.tombstones, first.alive + first.tombstones)

        XCTAssertEqual(first.alive.map(\.id), second.alive.map(\.id),
                       "re-merging a merged result must be a no-op, or the two machines push forever")
        XCTAssertEqual(first.tombstones.map(\.id), second.tombstones.map(\.id))
    }

    func testResultOrderIsStable() {
        let a = entry("A", "A", at: 10)
        let b = entry("B", "B", at: 20)

        XCTAssertEqual(merge([a], [b]).alive.map(\.wrong),
                       merge([b], [a]).alive.map(\.wrong),
                       "an unstable order would make each machine see a changed blob and push again")
    }

    // MARK: - Migration

    func testEntriesFromBeforeSyncStillDecodeAndMerge() throws {
        // A dictionary saved by 6.4.x: no modifiedAt, no deletedAt.
        let legacy = #"[{"id":"\#(UUID().uuidString)","wrong":"Hamer","right":"Hammer","kind":"always"}]"#
        let decoded = try JSONDecoder().decode([Correction].self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].modifiedAt, .distantPast,
                       "pre-sync entries must sort oldest so a real edit elsewhere wins")
        XCTAssertFalse(decoded[0].isDeleted)

        let newer = entry("Hamer", "Hamer", id: decoded[0].id, at: 10)
        XCTAssertEqual(merge(decoded, [newer]).alive.map(\.right), ["Hamer"])
    }
}
