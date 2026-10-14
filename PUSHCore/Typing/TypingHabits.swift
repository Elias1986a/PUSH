import Foundation

/// How the user usually finishes a phrase — "Thanks for sending this over.
/// I" → "'ll take a look tonight." — learned from all their finished writing,
/// in every app. Style, not content: a continuation is offered only once the
/// user has written it the same way at least `minimumCount` times, so a fact
/// from one thread never surfaces in another (the user's rule, 2026-10-11:
/// past passages stay window-specific; habits may travel, 2026-10-14).
/// Pure, so it is pinned by tests.
public struct TypingHabits: Sendable {
    /// Words of context matched before the caret, longest first.
    static let contextLengths = [4, 3]
    /// A habit, not a coincidence: seen at least this often…
    static let minimumCount = 3
    /// …and the way the user finishes it at least this share of the time.
    static let minimumShare = 0.6
    /// At most this many words are suggested, and never past a sentence end.
    static let maximumWords = 8
    /// Only the most recent writing of each record counts.
    static let charactersPerText = 4_000

    /// context → continuation length → continuation → count.
    private let table: [String: [Int: [String: Int]]]

    public init(texts: [String]) {
        var table: [String: [Int: [String: Int]]] = [:]
        for text in texts {
            let tokens = Self.tokens(String(text.suffix(Self.charactersPerText)))
            for i in tokens.indices {
                let continuation = Self.continuation(in: tokens, from: i)
                guard !continuation.isEmpty else { continue }
                for n in Self.contextLengths where i >= n {
                    let key = Self.key(tokens[(i - n)..<i])
                    guard !key.isEmpty else { continue }
                    for length in 1...continuation.count {
                        let words = continuation.prefix(length).joined(separator: " ")
                        table[key, default: [:]][length, default: [:]][words, default: 0] += 1
                    }
                }
            }
        }
        self.table = table
    }

    public var isEmpty: Bool { table.isEmpty }
    /// How many distinct word contexts were seen (for the assessment).
    public var contextCount: Int { table.count }

    /// The user's usual next words after `before`, or nil when there is no
    /// clear habit. `before` must end at a word boundary; the result starts
    /// with a space when it does not already end in one.
    public func continuation(after before: String) -> String? {
        let endsWithSpace = before.last?.isWhitespace == true
        let tokens = Self.tokens(String(before.suffix(400)))
        // A newline ends the line being written: habits do not cross it.
        if before.last?.isNewline == true { return nil }
        for n in Self.contextLengths where tokens.count >= n {
            let key = Self.key(tokens.suffix(n))
            guard let lengths = table[key] else { continue }
            var best: String?
            for length in lengths.keys.sorted() {
                guard let counts = lengths[length] else { continue }
                let total = counts.values.reduce(0, +)
                guard let (words, count) = counts.max(by: { $0.value < $1.value }),
                      count >= Self.minimumCount, Double(count) / Double(total) >= Self.minimumShare,
                      best.map({ words.hasPrefix($0 + " ") }) ?? true
                else { break }   // longer continuations can only be rarer
                best = words
            }
            guard let best, best.split(separator: " ").count >= 2 else { continue }
            return endsWithSpace ? best : " " + best
        }
        return nil
    }

    // MARK: - Pieces

    /// Whitespace-separated tokens, punctuation kept; a line break is its own
    /// token so a continuation can stop there.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if n > 0 { result.append("\n") }
            result += line.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        return result
    }

    /// Up to `maximumWords` tokens from `i`, through the first sentence end,
    /// never across a line break.
    static func continuation(in tokens: [String], from i: Int) -> [String] {
        var words: [String] = []
        var j = i
        while j < tokens.count, words.count < maximumWords, tokens[j] != "\n" {
            words.append(tokens[j])
            if let last = tokens[j].last, ".!?".contains(last) { break }
            j += 1
        }
        return words
    }

    /// Context words compared without case or curly-quote differences.
    static func key<S: Sequence>(_ words: S) -> String where S.Element == String {
        let list = Array(words)
        guard !list.contains("\n") else { return "" }
        return list.map { $0.lowercased().replacingOccurrences(of: "’", with: "'") }.joined(separator: " ")
    }
}

/// How well the habits would have predicted the user's own writing: each
/// fold of the texts is replayed against habits learned from the others.
/// Numbers only — for the learning assessment, which never shows text.
public struct TypingHabitsAssessment: Equatable, Sendable {
    public var positions = 0       // word boundaries replayed
    public var offered = 0         // a habit continuation was offered
    public var firstWordRight = 0  // its first word was the user's next word
    public var allRight = 0        // all of it matched what the user wrote

    public static func measure(texts: [String], folds: Int = 5) -> TypingHabitsAssessment {
        var result = TypingHabitsAssessment()
        guard texts.count >= folds else { return result }
        for fold in 0..<folds {
            let training = texts.enumerated().filter { $0.offset % folds != fold }.map(\.element)
            let habits = TypingHabits(texts: training)
            for (i, text) in texts.enumerated() where i % folds == fold {
                let tokens = TypingHabits.tokens(String(text.suffix(TypingHabits.charactersPerText)))
                guard tokens.count > 3 else { continue }   // "ok thanks": nothing to replay
                for k in 3..<tokens.count where tokens[k - 1] != "\n" && tokens[k] != "\n" {
                    result.positions += 1
                    let before = tokens[..<k].joined(separator: " ") + " "
                    guard let offer = habits.continuation(after: before) else { continue }
                    result.offered += 1
                    let offered = offer.split(separator: " ").map(String.init)
                    let actual = Array(tokens[k...].prefix(offered.count))
                    if offered.first == actual.first { result.firstWordRight += 1 }
                    if offered == actual { result.allRight += 1 }
                }
            }
        }
        return result
    }
}
