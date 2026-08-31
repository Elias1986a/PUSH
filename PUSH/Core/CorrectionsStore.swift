import Foundation
import PUSHCore

/// User-defined word corrections (e.g. "Hammer" -> "Hamer") applied to transcriptions
/// after Whisper runs, to fix names/jargon Whisper consistently mishears.
///
/// Entries come in two kinds (see docs/plans/2026-07-01-context-aware-dictionary-design.md):
/// `.always` entries replace unconditionally (unique jargon), while `.contextual`
/// entries are gated by a `VerdictSource` so a homophone like "Hammer" the tool is
/// left alone when the person "Hamer" isn't the one being talked about.
@MainActor
final class CorrectionsStore: ObservableObject {
    static let shared = CorrectionsStore()

    struct Correction: Codable, Identifiable, Equatable {
        /// How the correction is applied. `.always` = unconditional replace;
        /// `.contextual` = only when the gate agrees the entity is meant.
        enum Kind: String, Codable { case always, contextual }

        var id = UUID()
        var wrong: String
        var right: String
        var kind: Kind
        /// Free-text hint for the gate, e.g. "a person named Hamer". Only used
        /// by `.contextual` entries.
        var entity: String?

        /// When this entry last changed. The tiebreaker when the same entry was
        /// edited on two machines — see `CloudSync.mergeCorrections`.
        var modifiedAt: Date

        /// Set instead of removing the entry. A sync that merges by id would
        /// otherwise resurrect anything deleted here from the other machine's
        /// copy, so a deletion has to be a fact that travels, not an absence.
        var deletedAt: Date?

        var isDeleted: Bool { deletedAt != nil }

        /// Identity for "the same correction added twice, independently". Two
        /// machines that each add "Hamer" produce different UUIDs and identical
        /// meaning; this is what lets the merge collapse them.
        var contentKey: String {
            "\(wrong.lowercased())→\(right.lowercased())|\(kind.rawValue)"
        }

        /// `entity` with the field's incidental whitespace removed, and blank
        /// treated as absent — what the user typed, not how they typed it.
        var normalizedEntity: String? {
            guard let trimmed = entity?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            return trimmed
        }

        /// Everything the user can edit. Deliberately excludes `id` and the
        /// timestamps: this is what decides whether an entry *changed*, which
        /// is what has to re-stamp `modifiedAt` so the edit can win a merge.
        func hasSameContent(as other: Correction) -> Bool {
            wrong == other.wrong
                && right == other.right
                && kind == other.kind
                && normalizedEntity == other.normalizedEntity
        }

        init(
            id: UUID = UUID(),
            wrong: String,
            right: String,
            kind: Kind = .always,
            entity: String? = nil,
            modifiedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.wrong = wrong
            self.right = right
            self.kind = kind
            self.entity = entity
            self.modifiedAt = modifiedAt
            self.deletedAt = deletedAt
        }

        // Back-compatible decoding: entries persisted before context-awareness
        // (v4.1.x) have no `kind`/`entity` keys, and entries from before sync
        // (≤6.4.x) have no timestamps. Both must decode rather than throw.
        enum CodingKeys: String, CodingKey {
            case id, wrong, right, kind, entity, modifiedAt, deletedAt
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            wrong = try c.decode(String.self, forKey: .wrong)
            right = try c.decode(String.self, forKey: .right)
            kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .always
            entity = try c.decodeIfPresent(String.self, forKey: .entity)
            // Pre-sync entries sort oldest, so a genuine edit on the other
            // machine always wins over an entry that predates timestamps.
            modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
            deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        }
    }

    /// The live dictionary. Unchanged in meaning for every consumer: tombstones
    /// never appear here.
    @Published var corrections: [Correction] = [] {
        didSet {
            // Rows in Settings bind straight into this array, so an edit
            // arrives here as a mutated element and nothing else. Without a
            // fresh `modifiedAt` the edit looks no newer than the other Mac's
            // copy, and the merge keeps that stale copy — which is exactly how
            // adding context to an existing entry failed to sync.
            guard !isReplacingWholeList else { save(); return }
            let stamped = Self.restamped(corrections, previous: oldValue)
            if stamped != corrections {
                isReplacingWholeList = true
                corrections = stamped   // the nested didSet saves
                isReplacingWholeList = false
                return
            }
            save()
        }
    }

    /// Set while the whole list is being replaced wholesale — a load or a sync
    /// merge — so those assignments are never mistaken for user edits and
    /// re-stamped. Re-stamping a merge result would make every pull look like a
    /// brand-new edit and ping-pong between machines forever.
    private var isReplacingWholeList = false

    /// Deleted entries, kept so the deletion can reach the other machine.
    /// Not published — nothing in the UI or the pipeline should see these.
    private(set) var tombstones: [Correction] = []

    static let userDefaultsKey = "customDictionaryCorrections"

    /// Verdict source for the contextual lane. Heuristic-only until a warm
    /// on-device model is wired in behind `VerdictSource` (5.0.0 Phase 2).
    nonisolated static let defaultVerdictSource: VerdictSource = HeuristicVerdictSource()

    private init() {
        load()
    }

    func addCorrection(wrong: String, right: String, kind: Correction.Kind = .always, entity: String? = nil) {
        let wrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wrong.isEmpty, !right.isEmpty else { return }
        let entity = entity?.trimmingCharacters(in: .whitespacesAndNewlines)
        corrections.append(Correction(
            wrong: wrong,
            right: right,
            kind: kind,
            entity: (entity?.isEmpty ?? true) ? nil : entity
        ))
    }

    /// Tombstone rather than erase, so the deletion survives a merge with a
    /// machine that still has the entry.
    func remove(_ correction: Correction) {
        guard let entry = corrections.first(where: { $0.id == correction.id }) else { return }
        var dead = entry
        dead.deletedAt = Date()
        dead.modifiedAt = dead.deletedAt!
        tombstones.append(dead)
        corrections.removeAll { $0.id == correction.id }  // triggers save()
    }

    /// Replace the whole dictionary from a merge, without re-stamping anything.
    /// `corrections`' own `didSet` persists it.
    func applyMerged(alive: [Correction], tombstones: [Correction]) {
        self.tombstones = tombstones
        isReplacingWholeList = true
        self.corrections = alive
        isReplacingWholeList = false
    }

    /// Stamp `modifiedAt` on entries whose content the user just changed.
    ///
    /// Only entries that were already present and whose timestamp the caller
    /// left alone are touched, so a merge result or a load passes through
    /// untouched and an edit that already carries its own timestamp is kept.
    nonisolated static func restamped(
        _ updated: [Correction],
        previous: [Correction],
        now: Date = Date()
    ) -> [Correction] {
        guard !previous.isEmpty else { return updated }
        let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return updated.map { entry in
            guard let old = before[entry.id],
                  !old.hasSameContent(as: entry),
                  old.modifiedAt == entry.modifiedAt
            else { return entry }
            var stamped = entry
            stamped.modifiedAt = now
            return stamped
        }
    }

    /// Everything the sync layer needs to publish: live entries and tombstones.
    var allForSync: [Correction] { corrections + tombstones }

    // MARK: - Application

    /// Full context-aware application: unconditional `.always` entries first,
    /// then gated `.contextual` entries via `source`. Async because the gate may
    /// consult an on-device model. Instruments gate latency (timings/counts only,
    /// never transcript text).
    nonisolated static func applyContextAware(
        _ corrections: [Correction],
        to text: String,
        using source: VerdictSource = defaultVerdictSource
    ) async -> String {
        let afterAlways = applyReplacements(corrections.filter { $0.kind == .always }, to: text)

        let contextual = corrections.filter { $0.kind == .contextual }
        guard !contextual.isEmpty else { return afterAlways }

        return await applyContextual(contextual, to: afterAlways, using: source)
    }

    /// Case-insensitive, whole-word replacement of every "wrong" with its
    /// "right" spelling. Used for the unconditional `.always` lane.
    nonisolated static func applyReplacements(_ corrections: [Correction], to text: String) -> String {
        guard !corrections.isEmpty else { return text }

        var result = text
        for correction in corrections {
            guard !correction.wrong.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: correction.wrong) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: correction.right)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }

    // MARK: - Contextual lane

    /// Collect every ambiguous match, judge the whole batch in one shot, then
    /// apply only the approved spans (right-to-left so earlier indices stay valid).
    private nonisolated static func applyContextual(
        _ corrections: [Correction],
        to text: String,
        using source: VerdictSource
    ) async -> String {
        var ranges: [Range<String.Index>] = []
        var candidates: [CorrectionCandidate] = []

        for correction in corrections {
            guard !correction.wrong.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: correction.wrong) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let full = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, options: [], range: full) {
                guard let r = Range(match.range, in: text) else { continue }
                ranges.append(r)
                candidates.append(CorrectionCandidate(
                    matchedText: String(text[r]),
                    location: match.range.location,
                    replacement: correction.right,
                    entity: correction.entity
                ))
            }
        }
        guard !candidates.isEmpty else { return text }

        let start = DispatchTime.now()
        let verdicts = await source.judge(sentence: text, candidates: candidates)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000

        // Guard against a source that returns the wrong count — treat missing as keep.
        func verdict(_ i: Int) -> CorrectionVerdict { i < verdicts.count ? verdicts[i] : .keep }

        // Build (range, replacement, verdict) and apply right-to-left.
        let items = ranges.indices
            .map { (range: ranges[$0], replacement: candidates[$0].replacement, verdict: verdict($0)) }
            .sorted { $0.range.lowerBound > $1.range.lowerBound }

        var result = text
        var appliedCount = 0
        var lastAppliedLower: String.Index?
        for item in items {
            guard item.verdict == .apply else { continue }
            // Skip a span that overlaps an already-applied (later) span.
            if let lower = lastAppliedLower, item.range.upperBound > lower { continue }
            result.replaceSubrange(item.range, with: item.replacement)
            lastAppliedLower = item.range.lowerBound
            appliedCount += 1
        }

        PushLogger.log("ContextGate: judged \(candidates.count) candidate(s) in \(String(format: "%.1f", elapsedMs))ms, applied \(appliedCount)")
        return result
    }

    // MARK: - Private

    /// True while `load()` runs. Assigning `corrections` fires `didSet`, and
    /// saving what was just read is both pointless and — before this guard —
    /// fatal: it ran during `shared`'s one-time initialiser.
    private var isLoading = false

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Correction].self, from: data) else {
            return
        }
        // One stored array holds both; they are split on the way in so the
        // published list stays exactly what it always was.
        tombstones = decoded.filter(\.isDeleted)
        corrections = decoded.filter { !$0.isDeleted }
    }

    private func save() {
        guard !isLoading else { return }
        let all = corrections + tombstones
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        // Passed by value: CloudSync must not read `shared` back while this is
        // running, which can be inside this type's own initialiser.
        CloudSync.shared.dictionaryDidChange(all)
    }
}
