import Foundation

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

        init(id: UUID = UUID(), wrong: String, right: String, kind: Kind = .always, entity: String? = nil) {
            self.id = id
            self.wrong = wrong
            self.right = right
            self.kind = kind
            self.entity = entity
        }

        // Back-compatible decoding: entries persisted before context-awareness
        // (v4.1.x) have no `kind`/`entity` keys and must decode as `.always`
        // rather than throwing.
        enum CodingKeys: String, CodingKey { case id, wrong, right, kind, entity }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            wrong = try c.decode(String.self, forKey: .wrong)
            right = try c.decode(String.self, forKey: .right)
            kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .always
            entity = try c.decodeIfPresent(String.self, forKey: .entity)
        }
    }

    @Published var corrections: [Correction] = [] {
        didSet { save() }
    }

    private static let userDefaultsKey = "customDictionaryCorrections"

    /// Verdict source for the contextual lane: the warm on-device model when
    /// ready, otherwise zero-latency heuristics (both fail-safe). See
    /// GateVerdictSource / LlamaGateEngine.
    nonisolated static let defaultVerdictSource: VerdictSource = GateVerdictSource()

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

    func remove(_ correction: Correction) {
        corrections.removeAll { $0.id == correction.id }
    }

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

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Correction].self, from: data) else {
            return
        }
        corrections = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(corrections) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
