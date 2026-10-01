import Foundation
import NaturalLanguage

/// California mode: removing casual "like" wherever it is not doing a job.
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - California mode

    /// Words after which "like" is the verb: "I like it", "would you like",
    /// "they like to hike". "should" is left out on purpose — "we should like
    /// totally do that" is the filler, and nobody says "should like" any more.
    private static let verbLikePredecessors: Set<String> = [
        "i", "you", "we", "they", "i'd", "you'd", "we'd", "they'd", "he'd", "she'd",
        "would", "wouldn't", "do", "does", "did", "don't", "doesn't", "didn't",
        "to", "might", "may", "will", "won't", "can", "can't", "could", "couldn't"
    ]

    /// Adverbs that can sit between a subject and the verb: "I'd really like
    /// that", "we also like it". Checked one word further back.
    private static let verbAdverbs: Set<String> = ["really", "also", "still", "genuinely", "actually", "truly"]

    /// Words after which "like" makes a comparison: "looks like rain", "feel
    /// like going", "something like that", "just like before".
    private static let comparisonPredecessors: Set<String> = [
        "look", "looks", "looked", "looking", "sound", "sounds", "sounded", "sounding",
        "feel", "feels", "felt", "feeling", "seem", "seems", "seemed", "seeming",
        "smell", "smells", "smelled", "taste", "tastes", "tasted", "act", "acts", "acted",
        "just", "more", "something", "anything", "nothing", "everything", "exactly",
        "much", "lot", "people", "things", "someone", "somebody"
    ]

    /// Words after which "like" points at something: "like this", "people like us".
    private static let comparisonSuccessors: Set<String> = [
        "this", "that", "these", "those", "me", "us", "him", "her", "them"
    ]

    /// Forms of "be" that introduce quoted speech: "he was like, no way".
    /// Shared with the default filler pass, which must keep these too.
    static let quotativeBe: Set<String> = [
        "was", "is", "am", "were", "are", "be", "been", "i'm", "he's", "she's", "it's",
        "you're", "we're", "they're", "that's"
    ]

    static let speechVerbs: Set<String> = [
        "said", "say", "mentioned", "told", "explained", "discussed", "promised", "thought"
    ]

    private static let numberWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "fifteen", "twenty", "thirty", "forty", "fifty", "sixty",
        "a", "an", "half", "hundred", "thousand", "million"
    ]

    /// Remove "like" everywhere it is filler, for someone who says it a lot.
    ///
    /// The default pass (`removeFillerLike`) removes only the shapes that cannot
    /// be anything else, because a wrong guess deletes a word the sentence
    /// needed. This one is opt-in (Settings ▸ Text ▸ California mode), so it
    /// turns that around: every "like" goes unless a rule says it is working —
    /// the verb, a comparison, "like I said", an approximation ("like 30
    /// minutes" means *about* 30), or quoted speech ("he was like, no way").
    /// "likes", "likely" and "unlike" are different words and never touched.
    public static func removeCasualLike(_ text: String) -> String {
        guard text.range(of: "like", options: .caseInsensitive) != nil else { return text }

        // Words with their ranges; apostrophes stay inside ("she's", "i'd").
        let pattern = try! NSRegularExpression(pattern: "[A-Za-z0-9'\u{2019}]+")
        let tokens: [(word: String, range: Range<String.Index>)] = pattern
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { m in
                Range(m.range, in: text).map {
                    (text[$0].lowercased().replacingOccurrences(of: "\u{2019}", with: "'"), $0)
                }
            }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        func tag(_ range: Range<String.Index>) -> NLTag? {
            tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
        }
        /// The first non-space character after `index`, if any.
        func nextChar(after index: String.Index) -> Character? {
            text[index...].first { !$0.isWhitespace }
        }
        /// Whether a sentence begins at `index`: start of text, or after . ! ?
        func opensSentence(_ index: String.Index) -> Bool {
            guard let previous = text[..<index].last(where: { !$0.isWhitespace }) else { return true }
            return ".!?".contains(previous)
        }

        var doomed: [(range: Range<String.Index>, opensSentence: Bool)] = []
        for (i, token) in tokens.enumerated() where token.word == "like" {
            let prev = i > 0 ? tokens[i - 1].word : ""
            let prevPrev = i > 1 ? tokens[i - 2].word : ""
            let next = i + 1 < tokens.count ? tokens[i + 1].word : ""
            let nextNext = i + 2 < tokens.count ? tokens[i + 2].word : ""
            let commaAfter = nextChar(after: token.range.upperBound) == ","
            let atStart = opensSentence(token.range.lowerBound)
            // Between two words with no punctuation, so prev really is adjacent.
            let prevAdjacent = i > 0 && text[tokens[i - 1].range.upperBound..<token.range.lowerBound]
                .allSatisfy(\.isWhitespace)

            // "Could you like send the numbers": a bare verb straight after means
            // "like" cannot be the verb itself, whatever precedes it. "-ing" is
            // excluded because a gerund is an object: "I like cooking".
            let bareVerbFollows = !commaAfter && i + 1 < tokens.count && !next.hasSuffix("ing")
                && tag(tokens[i + 1].range) == .verb
            let isVerb = prevAdjacent && !bareVerbFollows && (
                verbLikePredecessors.contains(prev)
                || (verbAdverbs.contains(prev) && verbLikePredecessors.contains(prevPrev))
                // "Kids like candy", "dogs like walks": a plural noun subject and
                // a noun object. The tagger reads "like" as a preposition even
                // here, so the verb is recognised by the shape around it.
                || (prev.hasSuffix("s") && tag(tokens[i - 1].range) == .noun
                    && i + 1 < tokens.count && [NLTag.noun, .determiner].contains(tag(tokens[i + 1].range))))
            let isComparison = (prevAdjacent && comparisonPredecessors.contains(prev))
                || (!commaAfter && comparisonSuccessors.contains(next))
            // "like 30 minutes" is about 30; "like 90s themes" and "like 8-bit"
            // are a decade and a style, not quantities. Only a bare number —
            // or a range, "like 2-3 days" — makes "like" mean "about".
            let nextIsQuantity: Bool = {
                guard i + 1 < tokens.count else { return false }
                if numberWords.contains(next) { return true }
                guard next.allSatisfy(\.isNumber) else { return false }
                let after = text[tokens[i + 1].range.upperBound...]
                if after.first == "-" { return after.dropFirst().first?.isNumber == true }
                return true
            }()
            let isApproximation = !commaAfter && nextIsQuantity
            let isQuotative = prevAdjacent && quotativeBe.contains(prev) && commaAfter
            let isLikeISaid = !commaAfter && ["i", "we", "you", "they", "he", "she"].contains(next)
                && speechVerbs.contains(nextNext)
            // "Like the others, she left." — opening a sentence with no comma
            // after it, "like" is a preposition doing work.
            let opensWithoutComma = atStart && !commaAfter

            if isVerb || isComparison || isApproximation || isQuotative || isLikeISaid || opensWithoutComma {
                continue
            }
            doomed.append((token.range, atStart))
        }
        guard !doomed.isEmpty else { return text }

        var result = text
        for (range, startsSentence) in doomed.reversed() {
            // Widen to the commas that only bracketed the filler: "was, like,
            // amazing" loses both, "then like, the" loses the one after.
            var lower = range.lowerBound
            var upper = range.upperBound
            let afterSpace = result[upper...].prefix(while: { $0 == " " })
            let hasTrailingComma = result[afterSpace.endIndex...].first == ","
            if hasTrailingComma { upper = result.index(after: afterSpace.endIndex) }
            let beforeSpace = result[..<lower].reversed().prefix(while: { $0 == " " })
            let commaIndex = result.index(lower, offsetBy: -beforeSpace.count)
            if hasTrailingComma, commaIndex > result.startIndex,
               result[result.index(before: commaIndex)] == "," {
                lower = result.index(before: commaIndex)
            }
            result.replaceSubrange(lower..<upper, with: "")
            // A sentence that opened with "Like," keeps its capital.
            if startsSentence, let first = result[lower...].firstIndex(where: { !$0.isWhitespace }) {
                result.replaceSubrange(first...first, with: result[first].uppercased())
            }
        }
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        return result.replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
    }
}
