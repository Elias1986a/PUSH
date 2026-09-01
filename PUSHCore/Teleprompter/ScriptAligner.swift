import Foundation

/// Tracks where in a prepared script the speaker currently is, given the
/// partial transcripts arriving from a streaming ASR engine.
///
/// This is forced alignment, not recognition: the script is known, so the only
/// question is which of its tokens the speaker just said. That makes it a
/// matcher rather than a model — no weights, no inference, no dependency.
///
/// Deliberately a pure value type with an injected clock. Every interesting
/// behaviour here (repeats, substitutions, skips, ad-libs, silence) is
/// reachable from a unit test without a microphone or a UI.
public struct ScriptAligner: Sendable {

    // MARK: - Tuning

    /// The numbers that decide how it feels. Grouped so tests can vary one
    /// without restating the rest.
    public struct Tuning: Sendable {
        /// How many trailing transcript tokens to match against the script.
        /// Long enough that a single mangled word can't carry the decision,
        /// short enough to stay inside one clause.
        public var tailLength = 6

        /// How far back the search may look. Non-zero because a speaker who
        /// repeats a word should not drag the cursor forward off a false match
        /// they never actually reached.
        public var lookBehind = 4

        /// How far ahead the search may look while tracking. Covers a skipped
        /// clause without opening the window wide enough for a repeated phrase
        /// to teleport the cursor.
        public var lookAhead = 25

        /// The forward window once adrift: wide enough to rejoin a script you
        /// left a sentence ago.
        public var adriftLookAhead = 60

        /// Mean token similarity the best candidate must clear to move the
        /// cursor. Below this we are off-script, and holding still is the
        /// correct answer.
        public var matchThreshold = 0.55

        /// Levenshtein ratio below which two tokens are simply different
        /// words rather than one word an engine spelled badly.
        public var fuzzyThreshold = 0.75

        /// How far ahead of the last match the display may be extrapolated, in
        /// tokens. Bounds how wrong prediction can be: if the reader stops
        /// dead, this is the most the prompter can run on before the state
        /// falls to adrift and it stops entirely.
        public var predictionCap = 3.0

        /// Silence, or unmatched speech, before we admit we've lost the thread.
        public var adriftAfter: TimeInterval = 1.5
        public var lostAfter: TimeInterval = 5.0

        public init() {}
    }

    // MARK: - Types

    /// One script word: what we match on, and where it lives in the original
    /// text so the view can highlight real characters rather than normalized
    /// ones.
    public struct Token: Sendable, Equatable {
        /// Lowercased, punctuation stripped, number words folded to digits.
        public let normalized: String
        /// Soundex of the alphabetic form. Carries the homophones that edit
        /// distance cannot: their/there, to/two, for/four.
        public let soundex: String
        /// Range in the original, un-normalized script.
        public let range: Range<String.Index>
    }

    public enum Tracking: Sendable, Equatable {
        /// Nothing matched yet; waiting at the top of the script.
        case idle
        /// Matches are landing. The cursor follows the speaker.
        case tracking
        /// Nothing has matched recently. Hold position and widen the forward
        /// search, so rejoining mid-sentence snaps back on.
        case adrift
        /// Nothing has matched for a long time. Hold, and say so — the reader
        /// has stopped, gone off-script, or cannot be heard, and none of those
        /// are reasons to move the script.
        case lost
    }

    /// Where the prompter should be, and how much to trust it.
    public struct Position: Sendable, Equatable {
        /// Token index. Always an observed match while voice-following; the
        /// session's timed fallback is what produces fractional values.
        public let cursor: Double
        public let state: Tracking

        public init(cursor: Double, state: Tracking) {
            self.cursor = cursor
            self.state = state
        }
    }

    // MARK: - Stored state

    public let script: String
    public let tokens: [Token]
    public let tuning: Tuning

    /// Index of the last token matched with confidence. -1 before the first
    /// match, which is what makes `.idle` distinguishable from "matched token 0".
    public private(set) var cursor: Int = -1
    public private(set) var state: Tracking = .idle

    private var lastMatchTime: TimeInterval?
    private var firstMatchTime: TimeInterval?
    /// When this take began, so a prompter that has never heard a word can say
    /// so rather than sitting at the top looking healthy.
    private var startedAt: TimeInterval?
    /// Tokens advanced through since the first match, for the pace estimate.
    private var advancedTokens: Int = 0

    // MARK: - Init

    public init(script: String, tuning: Tuning = Tuning()) {
        self.script = script
        self.tuning = tuning
        self.tokens = Self.tokenize(script)
    }

    // MARK: - Driving it

    /// Feed the latest partial transcript. Returns where the prompter should be.
    ///
    /// Partials from a streaming engine are cumulative and their tails are
    /// unstable — the final word is often half-formed. Only the trailing tokens
    /// are used, and the mean over them absorbs one bad word.
    @discardableResult
    public mutating func consume(partial: String, at now: TimeInterval) -> Position {
        let spoken = Self.tokenize(partial)
        guard !spoken.isEmpty, !tokens.isEmpty else { return tick(at: now) }

        let tail = Array(spoken.suffix(tuning.tailLength))
        if let match = bestMatch(for: tail) {
            if firstMatchTime == nil { firstMatchTime = now }
            if match > cursor { advancedTokens += match - cursor }
            cursor = match
            lastMatchTime = now
            state = .tracking
        }
        return tick(at: now)
    }

    /// Advance time without a new partial — silence, or speech that matched
    /// nothing. This is what demotes tracking to adrift to lost.
    ///
    /// The first call establishes when the take began, which is what the
    /// never-heard-anything timeout is measured from. The session ticks at 20Hz
    /// from the moment it starts, so that is the start; a caller that ticks late
    /// is telling this type the take began late.
    @discardableResult
    public mutating func tick(at now: TimeInterval) -> Position {
        if startedAt == nil { startedAt = now }

        guard let last = lastMatchTime else {
            // Nothing has ever matched. Wait quietly at first — the reader may
            // simply not have started — but past the lost threshold, say so.
            // Silence here is indistinguishable from a dead microphone, and a
            // prompter that looks healthy while hearing nothing is worse than
            // one that admits it.
            //
            // Reported as lost but deliberately not drifting: there is no
            // measured pace to drift at, and guessing forward would walk the
            // script away from a reader who has not said a word.
            let waited = now - (startedAt ?? now)
            state = waited >= tuning.lostAfter ? .lost : .idle
            return Position(cursor: Double(max(cursor, 0)), state: state)
        }

        let quiet = now - last
        if quiet >= tuning.lostAfter {
            state = .lost
        } else if quiet >= tuning.adriftAfter {
            state = .adrift
        } else {
            state = .tracking
        }

        return Position(cursor: Double(max(cursor, 0)), state: state)
    }

    /// Move the cursor by hand, when the speaker corrects it.
    ///
    /// Treated as ground truth: matching resumes from the new position, so the
    /// windowed search looks around where the speaker says they are rather than
    /// where it last thought they were.
    public mutating func seek(to index: Int, at now: TimeInterval) {
        guard !tokens.isEmpty else { return }
        cursor = min(max(index, 0), tokens.count - 1)
        lastMatchTime = now
        state = .tracking
    }

    /// Where the reader has most likely got to *now*, rather than where they
    /// were when the last partial landed.
    ///
    /// Streaming partials arrive about a chunk behind the speech they describe,
    /// so a display driven straight off `cursor` is structurally late — it
    /// cannot help but lag, however fast the animation chasing it. Spending the
    /// measured pace on closing that gap is the whole reason for measuring it.
    ///
    /// Only extrapolates while tracking, and only up to `predictionCap`. A
    /// reader who stops gets at most that much invented motion before the state
    /// falls to adrift and this returns the plain cursor again — which is what
    /// keeps a pause from moving the script.
    public func predictedCursor(at now: TimeInterval) -> Double {
        let base = Double(max(cursor, 0))
        guard state == .tracking,
              let last = lastMatchTime,
              let wpm = measuredWordsPerMinute
        else { return base }

        let ahead = (wpm / 60.0) * max(now - last, 0)
        return base + min(ahead, tuning.predictionCap)
    }

    /// The speaker's own pace, measured from tokens actually matched. Nil until
    /// there is enough of a run to mean anything.
    public var measuredWordsPerMinute: Double? {
        guard let first = firstMatchTime, let last = lastMatchTime else { return nil }
        let elapsed = last - first
        guard elapsed > 1.0, advancedTokens > 3 else { return nil }
        // Clamped: a burst of matches over a short window can imply an absurd
        // pace, and prediction multiplies whatever it is told.
        return min(max(Double(advancedTokens) / elapsed * 60.0, 60), 400)
    }

    /// Text of the token at `index`, for highlighting.
    public func text(at index: Int) -> String? {
        guard tokens.indices.contains(index) else { return nil }
        return String(script[tokens[index].range])
    }

    // MARK: - Matching

    /// Best script position for this transcript tail, or nil if nothing in the
    /// window is convincing.
    ///
    /// Windowed, never global. Searched globally, a repeated "and then" or "so"
    /// teleports the cursor across the document — the failure mode that makes
    /// naive implementations of this unusable.
    private func bestMatch(for tail: [Token]) -> Int? {
        let ahead = (state == .adrift || state == .lost) ? tuning.adriftLookAhead : tuning.lookAhead
        let lower = max(0, cursor - tuning.lookBehind)
        let upper = min(tokens.count - 1, cursor + ahead)
        guard lower <= upper else { return nil }

        var best: (index: Int, score: Double)?
        for end in lower...upper {
            let score = alignmentScore(tail: tail, endingAt: end)
            guard score >= tuning.matchThreshold else { continue }
            // Strictly-greater keeps the earliest of equally good candidates,
            // which is the anti-teleport tiebreak: on a repeated phrase the
            // nearest occurrence wins over the one further down the script.
            if best == nil || score > best!.score {
                best = (end, score)
            }
        }
        return best?.index
    }

    /// Mean similarity of the tail against the script ending at `end`, walking
    /// both backwards. Tokens that fall off the front of the script score zero
    /// rather than being skipped, so an alignment that only fits by hanging off
    /// the start is correctly penalised.
    private func alignmentScore(tail: [Token], endingAt end: Int) -> Double {
        var total = 0.0
        for offset in 0..<tail.count {
            let scriptIndex = end - offset
            guard scriptIndex >= 0 else { continue }
            let spokenToken = tail[tail.count - 1 - offset]
            total += Self.similarity(spokenToken, tokens[scriptIndex])
        }
        return total / Double(tail.count)
    }

    /// How alike two tokens are, 0...1.
    ///
    /// Three tiers, because they fail differently: exact is exact; soundex
    /// catches homophones an ASR engine legitimately picked the other spelling
    /// of; edit distance catches an engine that simply misheard.
    static func similarity(_ a: Token, _ b: Token) -> Double {
        if a.normalized == b.normalized { return 1.0 }
        if !a.soundex.isEmpty, a.soundex == b.soundex { return 0.9 }
        let ratio = levenshteinRatio(a.normalized, b.normalized)
        return ratio >= 0.75 ? ratio : 0.0
    }

    // MARK: - Tokenizing

    /// Split text into matchable tokens, keeping each one's range in the
    /// original so the view can highlight the real characters.
    static func tokenize(_ text: String) -> [Token] {
        var result: [Token] = []
        var start: String.Index?

        func flush(_ end: String.Index) {
            guard let s = start else { return }
            start = nil
            let raw = String(text[s..<end])
            let normalized = normalize(raw)
            guard !normalized.isEmpty else { return }
            result.append(Token(normalized: normalized, soundex: soundex(raw), range: s..<end))
        }

        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isLetter || text[i].isNumber || text[i] == "'" {
                if start == nil { start = i }
            } else {
                flush(i)
            }
            i = text.index(after: i)
        }
        flush(text.endIndex)
        return result
    }

    /// Lowercase, drop apostrophes, and fold small number words to digits so a
    /// script's "twelve" matches an engine's "12".
    static func normalize(_ raw: String) -> String {
        let cleaned = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        return numberWords[cleaned] ?? cleaned
    }

    private static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
        "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
        "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
        "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
        "eighty": "80", "ninety": "90", "hundred": "100", "thousand": "1000"
    ]

    /// Classic Soundex over the alphabetic part of a token.
    ///
    /// Computed from the raw word rather than the normalized one: "two"
    /// normalizes to "2", and a digit has no Soundex, but its homophone "to"
    /// still needs to match it.
    static func soundex(_ raw: String) -> String {
        let letters = Array(raw.lowercased().filter { $0.isLetter })
        guard let first = letters.first else { return "" }

        func code(_ c: Character) -> Character? {
            switch c {
            case "b", "f", "p", "v": return "1"
            case "c", "g", "j", "k", "q", "s", "x", "z": return "2"
            case "d", "t": return "3"
            case "l": return "4"
            case "m", "n": return "5"
            case "r": return "6"
            default: return nil
            }
        }

        var digits = ""
        var previous = code(first)
        for c in letters.dropFirst() {
            let current = code(c)
            // h and w are transparent: they don't break a run of like codes.
            if c == "h" || c == "w" { continue }
            if let current, current != previous { digits.append(current) }
            previous = current
            if digits.count == 3 { break }
        }
        return (String(first).uppercased() + digits).padding(toLength: 4, withPad: "0", startingAt: 0)
    }

    /// 1 for identical, 0 for nothing in common. Length-normalized so a
    /// one-character slip matters more in a short word than a long one.
    static func levenshteinRatio(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        let x = Array(a), y = Array(b)
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)

        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        let distance = Double(previous[y.count])
        return 1.0 - distance / Double(max(x.count, y.count))
    }
}
