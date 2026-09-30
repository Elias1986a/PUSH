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
    /// This function *deletes words the user actually said*, so a false
    /// positive is far worse than a miss — it silently loses meaning and the
    /// user may not notice until later. Hence the rules in
    /// `resolveFirstSelfCorrection`: a marker must be set off by punctuation,
    /// and the correction must be short. "actually" and "rather" stay out
    /// entirely: "I actually like it" and "I'd rather go" are ordinary speech.
    static let replacementMarkers = [
        "i mean", "i meant", "no wait", "wait no", "make that", "or rather",
        "sorry", "correction",
    ]

    /// Markers that abandon the sentence so far and start it again.
    static let restartMarkers = [
        "scratch that", "let me start over", "start over", "delete that"
    ]

    /// Markers that are ordinary words or phrases too ("I'm sorry", "you
    /// should delete that file", "we need to start over"), so they count only
    /// as an interjection set off by punctuation on *both* sides:
    /// "Dave, sorry, Sarah" or "…at four. Correction, five."
    static let interjectionOnlyMarkers: Set<String> = ["sorry", "correction", "delete that", "start over"]

    /// A correction longer than this is not treated as one. Real corrections
    /// are a word or three ("I mean the blue car"); a long run after "I mean"
    /// is a new thought, and counting it deleted a whole clause of real
    /// dictation (114 → 53 characters, 2026-09-27).
    static let maximumCorrectionWords = 4

    /// Resolve spoken self-corrections: "the red car, I mean the blue car"
    /// becomes "the blue car".
    ///
    /// The span rule for a replacement is that the correction is about as long
    /// as the thing it corrects — so it deletes as many words before the marker
    /// as the correction has after it, up to the next comma or sentence end.
    /// "the red car, I mean the blue car" replaces with three words, so three
    /// come off the front. That is a heuristic, and it is wrong when someone
    /// corrects three words with one; deciding the span properly is the job an
    /// LLM resolver would exist for.
    ///
    /// Deletion never crosses a sentence boundary, so a correction can't eat
    /// the sentence before it however the count lands — with one narrow
    /// exception, the trailing "…7.0. 8.0, sorry." (see `resolveTrailing`).
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

        // Every occurrence of every marker, in reading order.
        var candidates: [(range: Range<String.Index>, marker: String)] = []
        for marker in replacementMarkers + restartMarkers {
            var searchStart = lower.startIndex
            while let r = lower.range(of: marker, range: searchStart..<lower.endIndex) {
                searchStart = r.upperBound
                // Word boundaries, so "I meant" doesn't fire inside "I meantime".
                let startsClean = r.lowerBound == lower.startIndex
                    || !lower[lower.index(before: r.lowerBound)].isLetter
                let endsClean = r.upperBound == lower.endIndex
                    || !lower[r.upperBound].isLetter
                if startsClean, endsClean { candidates.append((r, marker)) }
            }
        }
        candidates.sort { $0.range.lowerBound < $1.range.lowerBound }

        for candidate in candidates {
            let isRestart = restartMarkers.contains(candidate.marker)

            // Set off by punctuation (or opening the text) in front: "what I
            // mean is" and "I think I mean it" are not corrections. Behind too,
            // for the markers that are also everyday words.
            let needsBreakAfter = interjectionOnlyMarkers.contains(candidate.marker)
            guard precededByBreak(text, at: candidate.range.lowerBound)
                || (!isRestart && !needsBreakAfter && mirrorsWordBefore(text, marker: candidate.range))
            else { continue }
            if needsBreakAfter && !followedByBreak(text, at: candidate.range.upperBound) { continue }

            let before = String(text[..<candidate.range.lowerBound])
            let sentenceStart = startOfLastSentence(in: before)
            let head = String(before[..<sentenceStart])
            let clause = String(before[sentenceStart...])

            // The comma or colon the model puts after a marker ("I mean, the
            // blue car") belongs to the marker and goes with it.
            let after = String(text[candidate.range.upperBound...])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:")))

            // "sorry" and "correction" with nothing after them in the sentence:
            // the correction came first ("before 7.0. 8.0, sorry.").
            let correction = correctionWords(in: after)
            if needsBreakAfter && !isRestart && correction.isEmpty {
                if let resolved = resolveTrailing(text, marker: candidate.range) { return resolved }
                continue
            }

            // A marker right next to another marker is someone *listing* them —
            // "common words are sorry, correction, I mean…" — not correcting.
            let allMarkers = replacementMarkers + restartMarkers
            let correctionText = correction.joined(separator: " ").lowercased()
            let clauseText = trimDangling(clause).lowercased()
            if allMarkers.contains(where: { correctionText.hasPrefix($0) || clauseText.hasSuffix($0) }) { continue }

            // "sorry, but…", "sorry about that": an apology, not a correction.
            if candidate.marker == "sorry", let first = correction.first?.lowercased(),
               ["but", "about", "for", "to", "that", "if", "i'm", "i", "again"].contains(first) { continue }

            // A replacement marker opening its sentence has nothing to correct
            // in it. Usually that is just how people talk — "I mean, Ultra's
            // been great" — and it stays. But the model often ends the sentence
            // before the fix ("…to Sarah? I mean John."), so a short fix that
            // lines up with the end of the previous sentence reaches back.
            if !isRestart && trimDangling(clause).isEmpty {
                if let resolved = resolveAcrossSentences(text, head: head, markerEnd: candidate.range.upperBound) {
                    return resolved
                }
                continue
            }

            // Nothing to correct with — drop the dangling marker and keep the text.
            if after.isEmpty { return trimDangling(before) }

            // The correction inherits the deleted words' capital, if they had
            // one — dictation into the middle of a sentence starts lowercase.
            let capitalize = clause.trimmingCharacters(in: .whitespaces).first?.isUppercase ?? false

            if isRestart {
                // "…delayed, scratch that. The launch is on track." — the
                // marker ended its sentence, and that period goes with it.
                let fresh = String(after.drop(while: { $0 == "." || $0.isWhitespace }))
                return join(head, fresh, capitalize: capitalize)
            }

            // Long runs after a marker are new thoughts, not corrections.
            guard correction.count <= maximumCorrectionWords else { continue }

            // The same words again, stronger — "cold, I mean very cold" — is
            // emphasis. Resolving it pasted "Very cold." for "It's cold, I mean
            // very cold.", deleting what the speaker was emphasising.
            if isEmphasis(after, of: clause) { continue }

            // Replacement: drop the span the correction replaces, capped at the
            // clause so the previous sentence is never touched.
            var kept = clause.split(whereSeparator: \.isWhitespace).map(String.init)
            kept.removeLast(min(replacedSpan(in: kept, by: correction), kept.count))

            // Joined, not concatenated: splitting the clause into words threw
            // away the space it opened with, so "target. Um, latency…" came
            // back as "target.Um, latency…".
            let left = kept.isEmpty ? head : join(head, kept.joined(separator: " "))
            return join(left, after, capitalize: capitalize)
        }
        return nil
    }

    /// "Can you send a letter to Sarah? I mean John." → "…to John?"
    ///
    /// Only when the whole sentence after the marker is the fix (one to four
    /// words, ending the sentence) and it lines up with the end of the
    /// previous sentence — the same first word, or the same kind of word: a
    /// number, day, month, or name. No word-count fallback here: reaching into
    /// another sentence is only safe when the two visibly correspond. A fix
    /// identical to what it would replace ("I love it. I mean it.") is not one.
    /// The previous sentence keeps its own terminator, so a question stays one.
    private static func resolveAcrossSentences(
        _ text: String, head: String, markerEnd: String.Index
    ) -> String? {
        // The fix: up to the first comma or sentence end, which must end it.
        let after = String(text[markerEnd...])
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:")))
        let stop = after.indices.first(where: {
            ",;.!?".contains(after[$0]) && isClauseBreak(after, at: $0)
        })
        if let stop, !".!?".contains(after[stop]) { return nil }
        let fix = String(after[..<(stop ?? after.endIndex)]).split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...maximumCorrectionWords).contains(fix.count) else { return nil }
        let remainder = stop.map { String(after[after.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""

        // The previous sentence, and the terminator it keeps.
        let previous = trimDangling(head)
        guard let terminator = previous.last, ".!?".contains(terminator) else { return nil }
        let body = String(previous.dropLast())
        let sentenceStart = startOfLastSentence(in: body)
        let earlier = String(body[..<sentenceStart])
        var words = body[sentenceStart...].split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }

        let normalized = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let firstFix = fix[0].trimmingCharacters(in: .punctuationCharacters)
        let reachStart = max(0, words.count - 6)
        let isName: (String, Int) -> Bool = { word, index in
            // Capitalised, not a number/day/month, and not just the sentence's
            // own capital.
            index > 0 && word.first?.isUppercase == true && correctionKind(word.lowercased()) == nil
        }
        var from: Int?
        if let i = normalized[reachStart...].lastIndex(of: firstFix.lowercased()) {
            from = i
        } else if let kind = correctionKind(firstFix.lowercased()),
                  var i = normalized[reachStart...].lastIndex(where: { correctionKind($0) == kind }) {
            // Back over the rest of a number said in words: "5 million" is one
            // number, and lining up on "million" alone kept the "5".
            while i > reachStart, correctionKind(normalized[i - 1]) == kind { i -= 1 }
            from = i
        } else if firstFix.first?.isUppercase == true, correctionKind(firstFix.lowercased()) == nil,
                  let i = (reachStart..<words.count).last(where: { isName(words[$0].trimmingCharacters(in: .punctuationCharacters), $0) }) {
            from = i
        }
        guard let from else { return nil }

        let replaced = normalized[from...].joined(separator: " ")
        let replacement = fix.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }.joined(separator: " ")
        guard replaced != replacement else { return nil }

        words.removeSubrange(from...)
        let sentence = (words + fix).joined(separator: " ") + String(terminator)
        let rebuilt = (earlier.isEmpty ? "" : trimDangling(earlier) + " ") + sentence
        return remainder.isEmpty ? rebuilt : rebuilt + " " + remainder
    }

    /// How many trailing words of `clause` the correction replaces.
    ///
    /// Lined up rather than counted where possible, because a correction often
    /// carries more than the slip: "It costs 20, correction, 25 dollars"
    /// replaces "20", not the two words "costs 20". In order:
    /// 1. the correction's first word also appears near the end of the clause
    ///    ("the red car, I mean the blue car") → from that word on;
    /// 2. its first word is a number, day or month and so is a word near the
    ///    end of the clause ("20" ↔ "25") → from that word on;
    /// 3. otherwise as many words as the correction has.
    /// Lining up never reaches back more than six words.
    private static func replacedSpan(in clause: [String], by correction: [String]) -> Int {
        let normalized = clause.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let reach = normalized.suffix(6)
        if let first = correction.first?.lowercased().trimmingCharacters(in: .punctuationCharacters) {
            if let i = reach.lastIndex(of: first) { return normalized.count - i }
            if let kind = correctionKind(first),
               let i = reach.lastIndex(where: { correctionKind($0) == kind }) {
                return normalized.count - i
            }
        }
        return correction.count
    }

    /// Intensifiers that turn a repeat into emphasis rather than a fix.
    private static let intensifiers: Set<String> = [
        "really", "very", "so", "super", "extremely", "incredibly", "totally",
        "completely", "absolutely", "pretty", "seriously", "truly", "quite"
    ]

    /// Whether what follows the marker is the end of `clause` said again with
    /// intensifiers in front: "expensive" → "really expensive", "close" →
    /// "really, really close". The intensifiers are skipped commas and all
    /// (the first comma would otherwise end it at "really,"); what they lead
    /// into runs to the next comma or sentence end, so "very cold, so bring a
    /// coat" compares "cold".
    private static func isEmphasis(_ after: String, of clause: String) -> Bool {
        let norm = { (w: String) in w.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let tokens = after.split(whereSeparator: \.isWhitespace).map(String.init)
        let lead = tokens.prefix(while: { intensifiers.contains(norm($0)) }).count
        guard lead > 0 else { return false }
        var core: [String] = []
        for token in tokens.dropFirst(lead) {
            core.append(norm(token))
            if let last = token.last, ",;.!?".contains(last) { break }
        }
        core.removeAll(where: \.isEmpty)
        guard !core.isEmpty else { return false }
        let tail = clause.split(whereSeparator: \.isWhitespace).map { norm(String($0)) }.filter { !$0.isEmpty }
        return tail.suffix(core.count).elementsEqual(core)
    }

    /// The correction itself: the words after a marker up to the next comma,
    /// semicolon or sentence end. "I mean the blue car, which I love" is a
    /// three-word correction, not six.
    private static func correctionWords(in after: String) -> [String] {
        let end = after.indices.first(where: {
            ",;.!?".contains(after[$0]) && isClauseBreak(after, at: $0)
        }) ?? after.endIndex
        return after[..<end]
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    /// The trailing form: "…before 7.0. 8.0, sorry." — the fix is the short
    /// phrase just before the marker, and it replaces the same number of words
    /// before *it*, even across the sentence break the model tends to put
    /// between them.
    ///
    /// Only when the two are the same kind of thing — a number for a number, a
    /// time for a time, a weekday or month for another — because otherwise
    /// "Thanks for waiting, sorry." would delete three words of the sentence
    /// before. Returns nil (leave the text alone) whenever that can't be shown.
    private static func resolveTrailing(_ text: String, marker: Range<String.Index>) -> String? {
        let before = trimDangling(String(text[..<marker.lowerBound]))
        let rest = String(text[marker.upperBound...])

        // The fix: everything after the last comma or sentence end — one that
        // is followed by a space, so the dot inside "8.0" doesn't count.
        let chars = Array(before.indices)
        guard let boundary = chars.last(where: { i in
            let next = before.index(after: i)
            return ",;.!?".contains(before[i]) && next < before.endIndex && before[next].isWhitespace
        }) else { return nil }
        let fix = before[before.index(after: boundary)...].split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...3).contains(fix.count) else { return nil }

        // What it replaces: the same number of words just before that break.
        var earlier = String(before[...boundary]).split(whereSeparator: \.isWhitespace).map(String.init)
        guard earlier.count >= fix.count else { return nil }
        let replaced = earlier.suffix(fix.count).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        guard zip(replaced, fix).allSatisfy({ correctionKind($0) != nil && correctionKind($0) == correctionKind($1) })
        else { return nil }

        earlier.removeLast(fix.count)
        let fixed = (earlier + fix).joined(separator: " ")
        let tail = rest.trimmingCharacters(in: .whitespaces)
        return fixed + (tail.first.map { ".!?".contains($0) } == true ? tail : ". " + tail)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The kind of a word, for the trailing form's same-kind check.
    private static func correctionKind(_ word: String) -> String? {
        let w = word.lowercased()
        if w.range(of: #"^\d+(?:[.,:]\d+)*(?:%|am|pm|st|nd|rd|th)?$"#, options: .regularExpression) != nil {
            return "number"
        }
        let numberWords: Set<String> = ["one", "two", "three", "four", "five", "six", "seven", "eight",
                                        "nine", "ten", "eleven", "twelve", "twenty", "thirty", "forty",
                                        "fifty", "hundred", "thousand", "million"]
        if numberWords.contains(w) { return "number" }
        let days: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
                                 "sunday", "today", "tomorrow", "yesterday", "tonight"]
        if days.contains(w) { return "day" }
        let months: Set<String> = ["january", "february", "march", "april", "may", "june", "july",
                                   "august", "september", "october", "november", "december"]
        if months.contains(w) { return "month" }
        return nil
    }

    /// Whether the nearest non-space character before `index` is punctuation
    /// or the start of the text.
    /// "15.2 seconds I mean 1.52 seconds", "the red car I mean the blue car":
    /// no pause mark before the marker — the model does not always write one —
    /// but the correction ends on the very word the marker follows, which is
    /// what a correction looks like and ordinary speech ("what I mean is",
    /// "I think I mean it") does not.
    private static func mirrorsWordBefore(_ text: String, marker: Range<String.Index>) -> Bool {
        func bare(_ word: Substring) -> String {
            word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
        guard let previous = text[..<marker.lowerBound].split(whereSeparator: \.isWhitespace).last.map(bare),
              !previous.isEmpty else { return false }
        let correction = correctionWords(in: String(text[marker.upperBound...]))
        guard (1...maximumCorrectionWords).contains(correction.count),
              let last = correction.last?.split(whereSeparator: \.isWhitespace).last.map(bare) else { return false }
        return last == previous
    }

    private static func precededByBreak(_ text: String, at index: String.Index) -> Bool {
        guard let previous = text[..<index].last(where: { !$0.isWhitespace }) else { return true }
        return ",;:.!?—-".contains(previous)
    }

    /// Whether the nearest non-space character after `index` is punctuation or
    /// the end of the text.
    private static func followedByBreak(_ text: String, at index: String.Index) -> Bool {
        guard let next = text[index...].first(where: { !$0.isWhitespace }) else { return true }
        return ",;:.!?—-".contains(next)
    }

    /// Whether the punctuation at `index` ends a clause, or is sitting inside a
    /// number.
    ///
    /// "latency came back at 15.2 seconds, I mean 1.52 seconds" holds three
    /// dots and one sentence: the decimal points are followed by a digit, the
    /// terminator by a space. Reading a decimal point as a sentence end split
    /// the correction "1.52" into "1" and rebuilt the sentence around it —
    /// "came back at 15. 1. 52 seconds". `resolveTrailing` has applied this
    /// rule since it was written; the other passes had not, and the fixed
    /// benchmark script walked into it (2026-09-29).
    ///
    /// Digits only, deliberately. Requiring whitespace after the terminator
    /// would also reclassify "p.m." and every other abbreviation, which is a
    /// larger change than the bug warrants.
    private static func isClauseBreak(_ text: String, at index: String.Index) -> Bool {
        let next = text.index(after: index)
        guard next < text.endIndex else { return true }
        return !text[next].isNumber
    }

    /// Index just past the previous sentence's terminator, or the start.
    private static func startOfLastSentence(in text: String) -> String.Index {
        guard let terminator = text.indices.last(where: {
            ".!?".contains(text[$0]) && isClauseBreak(text, at: $0)
        }) else { return text.startIndex }
        return text.index(after: terminator)
    }

    /// Joins what was kept with the correction. When the correction now opens
    /// a sentence it takes the capital the deleted words had: "Red, I mean
    /// blue" → "Blue", not "blue".
    private static func join(_ left: String, _ right: String, capitalize: Bool = false) -> String {
        let head = trimDangling(left)
        let opensSentence = head.isEmpty || ".!?".contains(head.last!)
        let tail = opensSentence && capitalize ? right.prefix(1).uppercased() + right.dropFirst() : right
        if head.isEmpty { return tail }
        return head + " " + tail
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
