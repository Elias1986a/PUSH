import Foundation

/// Spoken quotation marks — "he said quote I'll be there end quote".
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - Spoken quotes

    /// Turns spoken quote markers into quotation marks.
    ///
    /// - "quote … end quote" (also "unquote", "close quote", "open quote",
    ///   "begin quote"): the marker words go, the words between them are quoted.
    /// - "and I quote …" keeps its words — it is how people write it too — and
    ///   quotes what follows, up to an end marker or the end of the sentence.
    ///   "open quote …" with no end marker closes at the end of the sentence.
    /// - A bare "quote" with no end marker is left alone: "get a quote from the
    ///   contractor" and "my favourite quote" are ordinary English, and turning
    ///   them into quotation marks would be worse than missing a real one.
    ///
    /// Straight quotes, because they paste correctly into every app.
    public static func normalizeSpokenQuotes(_ text: String) -> String {
        var result = text
        let opener = "(and\\s+I\\s+quote|(?:open\\s+|begin\\s+)?quote)"
        let closer = "(?:end\\s+(?:of\\s+)?quote|close\\s+quote|unquote)"

        // One character of a sentence: anything but a sentence end. A period
        // after a lone letter ("p.m.", "e.g.", "U.S.") or a title ("Dr.") is an
        // abbreviation, not an end — "at 3:30 p.m. tomorrow, end quote" is one
        // sentence.
        let unit = "(?:(?![.!?](?:\\s|$)).|(?<=\\b[A-Za-z])\\.|(?<=\\b(?:Mr|Mrs|Ms|Dr|St|vs|etc))\\.)"

        // Paired: an opener, the quoted words, a closer — within one sentence.
        // Spanning sentences let "and I quote blah. … end quote." swallow
        // everything between them. The model often wraps the markers in commas
        // ("said, quote, I'll be there, end quote, and"), so a comma after the
        // opener and before the closer belongs to the markers; a sentence end
        // just before the closer ("do not enter. End quote.") stays with the
        // quote.
        //
        // After the closer, American style: a period or comma moves inside the
        // quote; a question or exclamation mark stays outside, because it
        // belongs to the whole sentence ("Did he really say "yes"?").
        let paired = "(?i)\\b" + opener + "\\b[,:]?\\s+(" + unit + "+?)([.!?])?,?\\s+\\b"
            + closer + "\\b([,.!?;]?)"
        result = replaceAll(paired, in: result) { groups in
            let (marker, quoted, inner, trailing) = (groups[0], groups[1], groups[2], groups[3])
            let moves = trailing == "." || trailing == ","
            let body = joinPunctuation(quoted + inner, moves ? trailing : "")
            return prefix(for: marker) + "\"" + body + "\"" + (moves ? "" : trailing)
        }

        // Unpaired openers that clearly mean a quotation: close at the end of
        // the sentence (or of the dictation), its punctuation inside — the
        // quote runs to the sentence end, so the end is the quote's.
        let unpaired = "(?i)\\b(and\\s+I\\s+quote|open\\s+quote|begin\\s+quote)\\b[,:]?\\s+(?!\")("
            + unit + "+?)(?:((?<!\\b[A-Za-z])(?<!\\b(?:Mr|Mrs|Ms|Dr|St|vs|etc))\\.|[!?])(?=\\s|$)|$)"
        result = replaceAll(unpaired, in: result) { groups in
            let (marker, quoted, trailing) = (groups[0], groups[1], groups[2])
            let trimmed = quoted.trimmingCharacters(in: .whitespaces)
            return prefix(for: marker) + "\"" + joinPunctuation(trimmed, trailing) + "\""
        }
        return result
    }

    /// What is kept of the opener: "and I quote" stays as written (with the
    /// comma it takes before a quotation); every other opener is dropped.
    private static func prefix(for marker: String) -> String {
        let collapsed = marker.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.lowercased() == "and i quote" ? collapsed + ", " : ""
    }

    /// Put the punctuation that followed the closer inside the quotes, unless
    /// the quoted words already end in punctuation of their own.
    private static func joinPunctuation(_ quoted: String, _ trailing: String) -> String {
        guard !trailing.isEmpty, let last = quoted.last, !".,!?;".contains(last) else { return quoted }
        return quoted + trailing
    }

    /// Replace every match of `pattern`, handing the closure the text of each
    /// capture group (empty for a group that did not participate).
    private static func replaceAll(
        _ pattern: String, in text: String, with build: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let groups = (1..<match.numberOfRanges).map { i -> String in
                guard let r = Range(match.range(at: i), in: result) else { return "" }
                return String(result[r])
            }
            result.replaceSubrange(whole, with: build(groups))
        }
        return result
    }
}
