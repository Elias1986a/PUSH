import Foundation
import NaturalLanguage

/// Capitalization, filler words and the small typographic fixes every
/// engine's output needs.
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - Text Post-Processing

    /// Capitalize the first letter of the text and the first letter after sentence-ending punctuation
    /// Opening punctuation a sentence can start behind, so `. "hello` still
    /// capitalises. Everything else counts as content.
    private static let sentenceStartPassThrough: Set<Character> = ["\"", "'", "\u{201C}", "\u{2018}", "(", "["]

    public static func fixCapitalization(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        var capitalizeNext = true

        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
                if char == "." || char == "?" || char == "!" {
                    capitalizeNext = true
                } else if char.isWhitespace || sentenceStartPassThrough.contains(char) {
                    // Transparent: a pending sentence start survives the gap.
                } else {
                    // Any other content — digit, symbol, letter — occupies the
                    // sentence start, so nothing later gets capitalised for it.
                    // Clearing only on letters left the flag armed across digits
                    // and it landed on the next letter it found: "31st" → "31St",
                    // "142 people" → "142 People", "50% of" → "50% Of". The
                    // decimal point in "$2.5 million" re-armed it — "Million".
                    capitalizeNext = false
                }
            }
        }

        return result
    }

    /// Capitalize standalone "i" → "I" (the pronoun, not inside words)
    public static func capitalizeI(_ text: String) -> String {
        // Match standalone "i" surrounded by word boundaries
        guard let regex = try? NSRegularExpression(pattern: "\\bi\\b", options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "I")
    }

    /// Add double space after sentence-ending punctuation (. ? !).
    /// Note: this can't distinguish abbreviations ("Dr. Smith" also gets two
    /// spaces), which is part of why it's user-toggleable.
    public static func doubleSpaceAfterPeriods(_ text: String) -> String {
        var result = text
        // Replace single space after sentence-ending punctuation with double space
        for punct in [".", "?", "!"] {
            result = result.replacingOccurrences(of: "\(punct) ", with: "\(punct)  ")
            // Fix triple+ spaces back to double (in case already double-spaced)
            while result.contains("\(punct)   ") {
                result = result.replacingOccurrences(of: "\(punct)   ", with: "\(punct)  ")
            }
        }
        return result
    }

    /// Remove filler words: "um", "uh" always; "like" only when comma-bounded filler
    public static func removeFillerWords(_ text: String) -> String {
        var result = text

        // "like" is the hard one: it is a filler and an ordinary verb and a
        // comparison and an approximation, so only shapes that cannot be any of
        // the other three are stripped.
        //
        // Left alone on purpose:
        //   verb           "I like it"
        //   comparison     "looks like rain", "like this", "was like a dream"
        //   approximation  "like 30 minutes" — dropping it changes the number's
        //                  meaning from about-thirty to exactly-thirty
        //
        // Comma-bounded filler: "I was, like, going".
        //
        // Both commas go, not just the word. They were only there to bracket
        // the filler, and leaving one behind produced "I was, going" — the
        // filler removed and a comma splice left in its place.
        if let likeRegex = try? NSRegularExpression(pattern: ",\\s*like\\s*,\\s*", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = likeRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }

        // Sentence-initial: "Like, I don't know" — nothing precedes it to
        // compare to, so it cannot be the comparison sense.
        if let regex = try? NSRegularExpression(
            pattern: "(^|(?<=[.!?])\\s+)like\\s*,\\s*",
            options: .caseInsensitive
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }

        result = removeFillerLike(result)

        // Remove standalone "um" and "uh" (with surrounding commas/spaces)
        // Patterns: ", um," / ", uh," / "Um, " at start / " um " mid-sentence
        for filler in ["um", "uh"] {
            // Mid-sentence with commas: ", um," — both commas go with it, for
            // the same reason as the filler "like" above.
            if let regex = try? NSRegularExpression(pattern: ",\\s*\(filler)\\s*,\\s*", options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
            }
            // Start of text: "Um, " or "Uh, "
            if let regex = try? NSRegularExpression(pattern: "^\\s*\(filler)\\s*,?\\s*", options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
            // Standalone mid-sentence: " um " (no commas)
            if let regex = try? NSRegularExpression(pattern: "\\s+\(filler)\\s+", options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
            }
        }

        // Clean up any double spaces left behind
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
