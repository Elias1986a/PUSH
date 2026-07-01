import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Candidate & verdict

/// A Sendable projection of an ambiguous `.contextual` match, handed to a
/// `VerdictSource`. The transcript spans themselves stay in `CorrectionsStore`;
/// only this value crosses into the (possibly actor-isolated) judge.
struct CorrectionCandidate: Sendable, Equatable {
    /// The word exactly as it appears in the transcript (e.g. "Hammer").
    let matchedText: String
    /// UTF-16 offset of the match within the sentence — used to inspect the
    /// surrounding words and to keep candidate order stable.
    let location: Int
    /// What the word would become if the entity is meant (the entry's `right`).
    let replacement: String
    /// User-supplied hint about the entity, e.g. "a person named Hamer".
    let entity: String?
}

/// Whether to apply a candidate's replacement or keep the transcript untouched.
enum CorrectionVerdict: Sendable, Equatable { case apply, keep }

/// Judges a batch of ambiguous candidates against the full sentence in a single
/// shot. Implementations MUST be fail-safe: on any uncertainty, error, or
/// timeout, return `.keep` so correct transcription is never corrupted.
///
/// Batched (not per-candidate) by contract so latency stays ~constant regardless
/// of how many candidates a sentence contains — the property that keeps the
/// on-device model inside the ~200 ms budget.
protocol VerdictSource: Sendable {
    func judge(sentence: String, candidates: [CorrectionCandidate]) async -> [CorrectionVerdict]
}

// MARK: - Heuristic gate (Phase 1 default; also the pre-filter for the LLM lane)

enum CorrectionHeuristics {
    /// Words that, immediately before a candidate, signal a person/entity is
    /// meant rather than the ordinary word ("email **to** Hammer").
    static let entityTriggers: Set<String> = [
        "to", "from", "with", "cc", "bcc", "dear", "hi", "hello", "hey",
        "email", "emailed", "call", "called", "text", "texted", "message",
        "messaged", "tell", "told", "ask", "asked", "meet", "meeting", "met",
        "thanks", "regards", "@"
    ]

    /// Confident the entity (not the common word) is meant?
    /// `true` → apply. `false` → not confident, keep (fail-safe).
    static func entityLikely(sentence: String, candidate: CorrectionCandidate) -> Bool {
        let ns = sentence as NSString
        let matchLen = (candidate.matchedText as NSString).length
        guard candidate.location >= 0, candidate.location + matchLen <= ns.length else {
            return false
        }
        let before = ns.substring(to: candidate.location)

        // Signal 1: the token immediately before the match is a name/address cue.
        let prevToken = before
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .last
            .map { String($0).trimmingCharacters(in: .punctuationCharacters).lowercased() } ?? ""
        if !prevToken.isEmpty, entityTriggers.contains(prevToken) { return true }

        // Signal 2: capitalized mid-sentence (not sentence-initial) → proper name.
        if let first = candidate.matchedText.first, first.isUppercase {
            var b = before
            while let last = b.last, last == " " || last == "\n" || last == "\t" { b.removeLast() }
            let sentenceInitial = b.isEmpty || (b.last.map { ".!?".contains($0) } ?? true)
            if !sentenceInitial { return true }
        }

        return false
    }
}

/// The default, zero-latency verdict source: applies a correction only when the
/// heuristics are confident the entity is meant. Ships today; also serves as the
/// pre-filter that shrinks what a future LLM lane must judge.
struct HeuristicVerdictSource: VerdictSource {
    func judge(sentence: String, candidates: [CorrectionCandidate]) async -> [CorrectionVerdict] {
        candidates.map {
            CorrectionHeuristics.entityLikely(sentence: sentence, candidate: $0) ? .apply : .keep
        }
    }
}

// MARK: - LLM lane seam (Phase 2)

/// Pure prompt/parse helpers for the batched warm-LLM gate. Kept separate and
/// side-effect-free so they are unit-testable without a model, and so a concrete
/// `VerdictSource` backed by SwiftLlama can drop in behind `VerdictSource`
/// (see docs/plans/2026-07-01-context-aware-dictionary-design.md) without
/// touching the pipeline.
enum ContextGatePrompt {
    /// System instruction. Validated in the 5.1.0 POC: without the "names sound
    /// like common words" framing + few-shot below, a 0.5B model defaults every
    /// candidate to ORDINARY.
    static let systemPrompt = """
    You decide, from sentence context, whether an ambiguous word is being used as \
    the SPECIFIC ENTITY described, or as its ordinary everyday meaning. Names often \
    sound like common words. Reply one line per candidate: "<number> ENTITY" or \
    "<number> ORDINARY". Output only those lines.
    """

    /// Few-shot (user, assistant) turns that teach both the judgement and the
    /// output format. These lifted 0.5B accuracy from 5/12 to 10–11/12.
    static let fewShot: [(user: String, assistant: String)] = [
        ("Sentence: \"Please forward the email to Hammer.\"\nCandidate 1: \"Hammer\" (entity: a person named Hamer)",
         "1 ENTITY"),
        ("Sentence: \"He grabbed a hammer from the shed.\"\nCandidate 1: \"hammer\" (entity: a person named Hamer)",
         "1 ORDINARY"),
        ("Sentence: \"Ask Hammer and bring the hammer.\"\nCandidate 1: \"Hammer\" (entity: a person named Hamer)\nCandidate 2: \"hammer\" (entity: a person named Hamer)",
         "1 ENTITY\n2 ORDINARY"),
    ]

    /// The user message for one batch — the sentence plus every numbered candidate
    /// with its entity hint.
    static func userMessage(sentence: String, candidates: [CorrectionCandidate]) -> String {
        var lines = ["Sentence: \"\(sentence)\""]
        for (i, c) in candidates.enumerated() {
            let hint = c.entity ?? "the entity \"\(c.replacement)\""
            lines.append("Candidate \(i + 1): \"\(c.matchedText)\" (entity: \(hint))")
        }
        return lines.joined(separator: "\n")
    }

    /// Parse "<n> ENTITY|ORDINARY" lines into an ordered verdict array. Any missing
    /// or garbled line defaults to `.keep` (fail-safe toward not correcting).
    static func parse(_ output: String, count: Int) -> [CorrectionVerdict] {
        guard count > 0 else { return [] }
        var verdicts = Array(repeating: CorrectionVerdict.keep, count: count)
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let leading = line.drop(while: { !$0.isNumber })
            let digits = leading.prefix(while: { $0.isNumber })
            guard let n = Int(digits), n >= 1, n <= count else { continue }
            // "ENTITY" → apply; "ORDINARY" (or anything else) stays keep.
            if line.uppercased().contains("ENTITY") { verdicts[n - 1] = .apply }
        }
        return verdicts
    }
}

// MARK: - Word check (UX aid)

/// Whether a word is an ordinary, correctly-spelled word — used to *suggest*
/// context mode when a user adds an entry whose "heard as" side is a real word
/// (and therefore ambiguous, like "Hammer").
enum WordChecker {
    static func isCommonWord(_ word: String) -> Bool {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard w.count > 1, w.allSatisfy({ $0.isLetter }) else { return false }
        #if canImport(AppKit)
        let misspelledRange = NSSpellChecker.shared.checkSpelling(of: w, startingAt: 0)
        return misspelledRange.location == NSNotFound
        #else
        return false
        #endif
    }
}
