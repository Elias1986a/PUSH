import Foundation
import NaturalLanguage

/// Filler "like", stutters, and the punctuation and symbol passes.
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - Filler "like"

    /// Words after which a preposition-tagged "like" is filler rather than a
    /// comparison. Negations, conjunctions and subject pronouns cannot be the
    /// left side of a comparison — "he like lives here" has nothing being
    /// compared — whereas a noun or a comparison verb can: "people like us",
    /// "looks like rain".
    private static let fillerLikePredecessors: Set<String> = [
        "not", "never", "and", "but", "so", "or",
        "i", "he", "she", "it", "they", "we", "you"
    ]

    /// Strip filler "like" using the on-device part-of-speech tagger.
    ///
    /// String patterns alone cannot do this. Measured against the tagger, the
    /// senses are not separable by the tag on "like" by itself — filler and
    /// comparison both come back `Preposition` — and they are not separable by
    /// the neighbouring words either, because "I like pizza" and "he like
    /// lives" have the same shape. It takes both: the tag rules out the verb,
    /// the neighbours rule out the comparison.
    ///
    /// Without the tag, a rule matching pronoun + "like" turns "I like pizza"
    /// into "I pizza". That is the whole reason this is not a regex.
    public static func removeFillerLike(_ text: String) -> String {
        guard text.range(of: "like", options: .caseInsensitive) != nil else { return text }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        // Collected first, applied last-to-first, so earlier ranges stay valid.
        var doomed: [Range<String.Index>] = []
        var previousWord = ""

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            let word = text[range].lowercased()
            defer { previousWord = word }
            guard word == "like" else { return true }

            switch tag {
            case .verb:
                // "I like it", "would like a coffee", and — because the tagger
                // labels it so — "do it like this". Never removed: this is the
                // case where a wrong guess destroys the sentence.
                return true

            case .interjection:
                // The tagger's own filler reading. Kept only before a number,
                // where it means "about": dropping it in "in like 30 minutes"
                // would turn an estimate into a precise claim.
                if !nextWordIsNumber(after: range, in: text) {
                    doomed.append(range)
                }

            case .preposition:
                // Ambiguous: both "looks like rain" and "not like irate". The
                // preceding word decides.
                if Self.fillerLikePredecessors.contains(previousWord),
                   !nextWordIsNumber(after: range, in: text) {
                    doomed.append(range)
                }

            default:
                break
            }
            return true
        }

        guard !doomed.isEmpty else { return text }

        var result = text
        for range in doomed.reversed() {
            result.replaceSubrange(range, with: "")
        }
        return result
    }

    private static func nextWordIsNumber(after range: Range<String.Index>, in text: String) -> Bool {
        let rest = text[range.upperBound...]
        guard let next = rest.split(whereSeparator: \.isWhitespace).first else { return false }
        return next.first?.isNumber ?? false
    }

    /// Remove stuttered/duplicate consecutive words: "the the" → "the", "I I" → "I"
    public static func removeStutteredWords(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b(\\w+)\\s+\\1\\b",
            options: .caseInsensitive
        ) else { return text }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }

    /// Fix question marks: sentences starting with question words should end with ?
    public static func fixQuestionMarks(_ text: String) -> String {
        let questionWords: Set<String> = [
            "who", "what", "where", "when", "why", "how",
            "is", "are", "am", "was", "were",
            "do", "does", "did",
            "can", "could", "would", "should", "shall", "will",
            "have", "has", "had",
            "isn't", "aren't", "don't", "doesn't", "didn't",
            "won't", "wouldn't", "couldn't", "shouldn't",
            "isn\u{2019}t", "aren\u{2019}t", "don\u{2019}t", "doesn\u{2019}t", "didn\u{2019}t",
            "won\u{2019}t", "wouldn\u{2019}t", "couldn\u{2019}t", "shouldn\u{2019}t"
        ]

        // Split into sentences on . or ? or !
        // Process each sentence: if it starts with a question word and ends with ., flip to ?
        var result = ""
        var current = ""

        for char in text {
            current.append(char)
            if char == "." || char == "?" || char == "!" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                let firstWord = trimmed.split(separator: " ").first.map { String($0).lowercased() } ?? ""

                if char == "." && questionWords.contains(firstWord) {
                    // Replace trailing period with question mark
                    let idx = current.lastIndex(of: ".")!
                    current.replaceSubrange(idx...idx, with: "?")
                }

                result.append(current)
                current = ""
            }
        }
        // Append any remaining text (no trailing punctuation)
        result.append(current)

        return result
    }

    /// Replace trailing comma with a period (model sometimes leaves a dangling comma)
    public static func fixTrailingComma(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix(",") {
            result = String(result.dropLast()) + "."
        }
        return result
    }

    /// Add a period at the end if there's no ending punctuation
    public static func ensureEndingPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let lastChar = trimmed.last!
        if lastChar == "." || lastChar == "?" || lastChar == "!" {
            return text
        }
        return trimmed + "."
    }

    /// Smart symbol replacement: "percent" → "%", "dollar" → "$", "at sign" → "@"
    public static func smartSymbols(_ text: String) -> String {
        var result = text

        // Number + "percent" → number + "%"  (e.g. "50 percent" → "50%")
        if let regex = try? NSRegularExpression(pattern: "(\\d)\\s+percent\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1%")
        }

        // "50 dollars" → "$50". The number must be matched whole: this pass runs
        // *after* comma-grouping, and a bare \d+ matched only the last group of
        // "5,000,000 dollars", which turned it into "5,000,$000". A trailing
        // magnitude word is part of the amount too — "5 million dollars" is
        // "$5 million", not "$5 million dollars".
        let amount = "\\d[\\d,]*(?:\\.\\d+)?"
        let magnitude = "(?:\\s+(?:hundred|thousand|million))?"
        if let regex = try? NSRegularExpression(pattern: "(?<![\\d.,])(\(amount)\(magnitude))\\s+dollars?\\b",
                                                options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "\\$$1")
        }

        // "at sign" or "at symbol" → "@"
        if let regex = try? NSRegularExpression(pattern: "\\bat\\s+sign\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "@")
        }

        // "hashtag" or "hash sign" → "#"
        if let regex = try? NSRegularExpression(pattern: "\\bhash\\s*tag\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "#")
        }

        // "ampersand" → "&"
        if let regex = try? NSRegularExpression(pattern: "\\bampersand\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "&")
        }

        return result
    }

    /// Strip the leading apostrophe Whisper adds to the contraction of "because":
    /// "'cause" → "cause" (handles straight and curly apostrophes, preserves casing).
    public static func normalizeCause(_ text: String) -> String {
        // (^|non-word) + apostrophe + "cause" word → drop the apostrophe, keep the boundary and word.
        guard let regex = try? NSRegularExpression(
            pattern: "(^|[^A-Za-z'\u{2019}])['\u{2019}](causes?)\\b",
            options: .caseInsensitive
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1$2")
    }
}
