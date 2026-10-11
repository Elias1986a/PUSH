import Foundation
import CryptoKit

/// One piece of the user's own writing: what was before the caret in one
/// field, the last time it was seen. Only recorded when "Learn from my
/// writing" is on (Settings → Personal); stored encrypted, never synced.
public struct TypingHistoryRecord: Codable, Sendable, Equatable {
    public var text: String
    public var bundleID: String
    public var date: Date

    public init(text: String, bundleID: String, date: Date = Date()) {
        self.text = text
        self.bundleID = bundleID
        self.date = date
    }
}

/// Takes out what must never be kept, even encrypted: pasted keys, card
/// numbers, long tokens. Prose passes untouched — only shapes a person
/// almost never types by hand are replaced.
public enum TypingHistoryScrubber {
    public static let redaction = "[redacted]"
    /// A record keeps its last this-many characters: recent wording is the
    /// point, and one huge document would crowd out everything else.
    public static let maximumCharacters = 12_000

    private static let patterns: [NSRegularExpression] = [
        // PEM private keys, whole.
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)"#,
        // Known credential prefixes (OpenAI/Anthropic, GitHub, Slack, AWS).
        #"\b(?:sk-[A-Za-z0-9_\-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16})"#,
        // Card-length digit runs (13–19 digits, maybe grouped); phone numbers are shorter.
        #"\b(?:\d[ \-]?){12,18}\d\b"#,
        // One unbroken 24+ character token with a digit in it: hashes, JWTs, base64.
        #"(?=[A-Za-z0-9_\-+/=.]*\d)[A-Za-z0-9_\-+/=.]{24,}"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func scrub(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            result = pattern.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: redaction)
        }
        return String(result.suffix(maximumCharacters))
    }
}

/// Finds the user's past passages that talk about what they are writing now,
/// for the prompt's "earlier writing" section. A plain word index with rarity
/// weights — no model, so it is instant, deterministic and testable.
public struct TypingHistoryIndex: Sendable {
    struct Passage: Sendable {
        let text: String
        let bundleID: String
        let words: Set<String>
    }

    /// Passages are cut to about this size at sentence ends.
    static let passageCharacters = 320
    /// Below this shared weight, a match is coincidence and only adds noise.
    static let minimumScore = 6.0
    static let sameAppBoost = 1.3

    let passages: [Passage]
    private let postings: [String: [Int]]
    private let rarity: [String: Double]

    public var passageCount: Int { passages.count }

    public init(records: [TypingHistoryRecord]) {
        var passages: [Passage] = []
        for record in records {
            for text in Self.passages(of: record.text) {
                let words = Self.words(text)
                if words.count >= 4 { passages.append(Passage(text: text, bundleID: record.bundleID, words: words)) }
            }
        }
        var postings: [String: [Int]] = [:]
        for (i, passage) in passages.enumerated() {
            for word in passage.words { postings[word, default: []].append(i) }
        }
        let n = Double(max(passages.count, 1))
        self.passages = passages
        self.postings = postings
        self.rarity = postings.mapValues { log(1 + n / Double($0.count)) }
    }

    /// Up to `limit` passages that share the most telling words with `query`,
    /// within `maxCharacters` all told. Never a passage already in
    /// `currentText` — showing the model the user's own draft makes it echo.
    public func examples(query: String, bundleID: String?, currentText: String,
                         limit: Int = 2, maxCharacters: Int = 760) -> [String] {
        let queryWords = Self.words(query)
        guard !queryWords.isEmpty else { return [] }
        var scores: [Int: Double] = [:]
        for word in queryWords {
            guard let hits = postings[word], let weight = rarity[word] else { continue }
            for i in hits { scores[i, default: 0] += weight }
        }
        var ranked: [(index: Int, score: Double)] = []
        for (i, score) in scores {
            let boosted = passages[i].bundleID == bundleID ? score * Self.sameAppBoost : score
            if boosted >= Self.minimumScore { ranked.append((i, boosted)) }
        }
        // Best first; on a tie, the newer passage.
        ranked.sort { a, b in a.score != b.score ? a.score > b.score : a.index > b.index }
        var chosen: [String] = []
        var used = 0
        for (i, _) in ranked where chosen.count < limit {
            let text = passages[i].text
            guard !currentText.contains(text.prefix(80)), used + text.count <= maxCharacters,
                  !chosen.contains(text) else { continue }
            chosen.append(text)
            used += text.count
        }
        return chosen
    }

    /// The text cut at sentence ends into pieces of about `passageCharacters`.
    static func passages(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            if !current.isEmpty, current.count + sentence.count + 1 > passageCharacters {
                result.append(current)
                current = ""
            }
            current += current.isEmpty ? sentence : " " + sentence
        }
        if !current.isEmpty { result.append(current) }
        return result.map { String($0.prefix(passageCharacters * 2)) }
    }

    /// Lowercased words of three letters or more, minus the commonest ones.
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") }
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) })
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was", "one", "our",
        "out", "has", "have", "his", "how", "its", "may", "who", "did", "get", "got", "him", "she", "too", "use",
        "that", "this", "with", "from", "they", "will", "would", "there", "their", "what", "about", "which",
        "when", "your", "been", "were", "them", "then", "than", "just", "also", "into", "some", "could", "should",
        "very", "much", "more", "here", "i'm", "it's", "don't", "i’m", "it’s", "don’t",
    ]
}

/// What a lookup searches for: the text before the caret rounded down to
/// whole blocks of words, so the examples (which sit in the prompt's head)
/// stay the same for several words and the KV cache keeps matching.
public enum TypingHistoryQuery {
    public static func stableText(_ before: String, wordsPerBlock: Int = 8, maxWords: Int = 48) -> String {
        let words = before.split(whereSeparator: \.isWhitespace)
        let complete = (words.count / wordsPerBlock) * wordsPerBlock
        guard complete > 0 else { return "" }
        return words[..<complete].suffix(maxWords).joined(separator: " ")
    }
}

/// History at rest: JSON sealed with AES-GCM. The key lives in the Keychain
/// (this Mac only); the app owns both.
public enum TypingHistoryCodec {
    public static func seal(_ records: [TypingHistoryRecord], key: SymmetricKey) throws -> Data {
        let json = try JSONEncoder().encode(records)
        guard let sealed = try AES.GCM.seal(json, using: key).combined else { throw CryptoKitError.incorrectParameterSize }
        return sealed
    }

    public static func open(_ data: Data, key: SymmetricKey) throws -> [TypingHistoryRecord] {
        let json = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        return try JSONDecoder().decode([TypingHistoryRecord].self, from: json)
    }
}

/// Whether a field's text is still the same piece of writing as before. A
/// field is reused: a chat box empties when a message is sent, a mail window
/// starts a new draft. Typing, deleting or fixing a word keeps most of the
/// text at its start or its end; carrying on past the end keeps the old
/// ending inside the new text (a long note's window moves forward too).
public enum TypingHistoryContinuity {
    public static func isSameWriting(old: String, new: String) -> Bool {
        if old.isEmpty || new.isEmpty { return true }
        let shorter = min(old.count, new.count)
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let suffix = zip(old.reversed(), new.reversed()).prefix { $0 == $1 }.count
        if prefix + suffix >= shorter / 2 { return true }
        let ending = old.suffix(min(old.count, 80))
        return ending.count >= 20 && new.contains(ending)
    }
}
