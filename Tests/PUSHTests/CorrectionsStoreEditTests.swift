import XCTest
@testable import PUSH

/// Editing an entry has to look like an edit to the sync layer.
///
/// Settings binds its rows straight into the stored array, so a change arrives
/// as a mutated element and nothing more. If `modifiedAt` stays where it was,
/// the other Mac's untouched copy of the same entry is no older, the merge has
/// no reason to prefer the edit, and the change never travels — which is how
/// adding context to an existing dictionary entry failed to sync.
final class CorrectionsStoreEditTests: XCTestCase {

    private typealias Correction = CorrectionsStore.Correction

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func restamp(_ updated: [Correction], _ previous: [Correction]) -> [Correction] {
        CorrectionsStore.restamped(updated, previous: previous, now: now)
    }

    func testAddingContextToAnExistingEntryIsStampedAsAnEdit() {
        let before = Correction(wrong: "Hamer", right: "Hammer", kind: .contextual, modifiedAt: t0)
        var after = before
        after.entity = "a person named Hamer"

        XCTAssertEqual(restamp([after], [before]).first?.modifiedAt, now,
                       "an edited entry that keeps its old timestamp loses the merge on the other Mac")
    }

    func testEveryEditableFieldCounts() {
        let before = Correction(wrong: "Hamer", right: "Hammer", kind: .always, modifiedAt: t0)

        let changes: [(inout Correction) -> Void] = [
            { $0.wrong = "Haymer" },
            { $0.right = "Hamer" },
            { $0.kind = .contextual },
            { $0.entity = "a person named Hamer" }
        ]

        for change in changes {
            var after = before
            change(&after)
            XCTAssertEqual(restamp([after], [before]).first?.modifiedAt, now)
        }
    }

    func testUntouchedEntriesKeepTheirTimestamp() {
        let entry = Correction(wrong: "Hamer", right: "Hammer", modifiedAt: t0)

        XCTAssertEqual(restamp([entry], [entry]).first?.modifiedAt, t0,
                       "re-stamping an unchanged entry would make every save look like an edit")
    }

    func testWhitespaceOnlyDifferencesInContextAreNotEdits() {
        let before = Correction(wrong: "Hamer", right: "Hammer", kind: .contextual,
                                entity: "a person named Hamer", modifiedAt: t0)
        var after = before
        after.entity = "  a person named Hamer  "

        XCTAssertEqual(restamp([after], [before]).first?.modifiedAt, t0)
    }

    func testNewEntriesAndMergeResultsPassThrough() {
        let existing = Correction(wrong: "Hamer", right: "Hammer", modifiedAt: t0)
        let added = Correction(wrong: "Parakeet", right: "Parakeet", modifiedAt: t0)
        XCTAssertEqual(restamp([existing, added], [existing]).map(\.modifiedAt), [t0, t0],
                       "an entry the previous list never had is not an edit of anything")

        // What a sync merge hands back: same id, different content, and a
        // timestamp the other machine already chose. Re-stamping it here would
        // make each pull look like a local edit and bounce between machines.
        var fromRemote = existing
        fromRemote.entity = "a person named Hamer"
        fromRemote.modifiedAt = t0.addingTimeInterval(60)
        XCTAssertEqual(restamp([fromRemote], [existing]).first?.modifiedAt, t0.addingTimeInterval(60))
    }
}
