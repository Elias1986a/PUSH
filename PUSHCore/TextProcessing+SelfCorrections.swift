import Foundation
import NaturalLanguage

/// Acting on a spoken correction — "the red car, I mean the blue car".
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - Spoken self-corrections

    /// Markers that replace what was just said: keep what follows, drop a
    /// comparable span before.
    ///
    /// Every one of these is a phrase, not a word, and that is the whole
    /// design. This function *deletes words the user actually said*, so a
    /// false positive is far worse than a miss — it silently loses meaning and
    /// the user may not notice until later. Bare "sorry", "actually" and
    /// "rather" are the obvious candidates and all three are excluded: "I'm
    /// sorry about that", "I actually like it", "I'd rather go" are ordinary
    /// speech, and there is no reliable way to tell them apart here. They are
    /// exactly the cases to hand to the LLM resolver later, not to guess at.
    static let replacementMarkers = [
        "i mean", "i meant", "no wait", "wait no", "make that", "or rather"
    ]

    /// Markers that abandon the sentence so far and start it again.
    static let restartMarkers = [
        "scratch that", "let me start over", "start over", "delete that"
    ]

    /// Resolve spoken self-corrections: "the red car, I mean the blue car"
    /// becomes "the blue car".
    ///
    /// The span rule for a replacement is that the correction is about as long
    /// as the thing it corrects — so it deletes as many words before the marker
    /// as the replacement has after it. "the red car, I mean the blue car"
    /// replaces with three words, so three come off the front. That is a
    /// heuristic, and it is wrong when someone corrects three words with one;
    /// deciding the span properly is the job the LLM resolver exists for.
    ///
    /// Deletion never crosses a sentence boundary, so a correction can't eat
    /// the sentence before it however the count lands.
    public static func resolveSelfCorrections(_ text: String) -> String {
        var result = text
        // Each pass resolves the first marker. The cap stops a pathological
        // transcript from looping; real speech never stacks this many.
        for _ in 0..<8 {
            guard let resolved = resolveFirstSelfCorrection(in: result) else { break }
            result = resolved
        }
        return result
    }

    /// One pass. Returns nil when there is no marker left to resolve.
    private static func resolveFirstSelfCorrection(in text: String) -> String? {
        let lower = text.lowercased()

        var found: (range: Range<String.Index>, isRestart: Bool)?
        for marker in replacementMarkers + restartMarkers {
            guard let r = lower.range(of: marker) else { continue }
            // Word boundaries, so "I meant" doesn't fire inside "I meantime".
            let startsClean = r.lowerBound == lower.startIndex
                || !lower[lower.index(before: r.lowerBound)].isLetter
            let endsClean = r.upperBound == lower.endIndex
                || !lower[r.upperBound].isLetter
            guard startsClean, endsClean else { continue }
            if found == nil || r.lowerBound < found!.range.lowerBound {
                found = (r, restartMarkers.contains(marker))
            }
        }
        guard let marker = found else { return nil }

        let before = String(text[..<marker.range.lowerBound])
        let after = String(text[marker.range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing to correct with — drop the dangling marker and keep the text.
        if after.isEmpty { return trimDangling(before) }

        let sentenceStart = startOfLastSentence(in: before)
        let head = String(before[..<sentenceStart])
        let clause = String(before[sentenceStart...])

        if marker.isRestart {
            return join(head, after)
        }

        // Replacement: drop as many words as the correction supplies, capped at
        // the clause so the previous sentence is never touched.
        let replacementLength = after
            .prefix { $0 != "." && $0 != "!" && $0 != "?" }
            .split(whereSeparator: \.isWhitespace)
            .count
        var kept = clause.split(whereSeparator: \.isWhitespace).map(String.init)
        kept.removeLast(min(replacementLength, kept.count))

        return join(head + kept.joined(separator: " "), after)
    }

    /// Index just past the previous sentence's terminator, or the start.
    private static func startOfLastSentence(in text: String) -> String.Index {
        guard let terminator = text.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" })
        else { return text.startIndex }
        return text.index(after: terminator)
    }

    private static func join(_ left: String, _ right: String) -> String {
        let head = trimDangling(left)
        if head.isEmpty { return right }
        return head + " " + right
    }

    /// Strip the whitespace and the comma left hanging by a removed span, so
    /// "the red car, " doesn't become "the red car ,".
    private static func trimDangling(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, last == "," || last == ";" || last == "-" {
            t.removeLast()
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }
}
