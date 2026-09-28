import Foundation

/// Spoken quotation marks — "he said quote I'll be there end quote".
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - Spoken quotes

    /// Turns spoken quote markers into quotation marks.
    ///
    /// - "quote … end quote" (also "unquote", "close quote", "open quote",
    ///   "begin quote"): the marker words go, the words between them are quoted,
    ///   across sentences if need be — "Quote Elias is here. Elias is here, end
    ///   quote." is one quotation.
    /// - Most people never say "end quote", so a "quote" that plainly opens a
    ///   quotation — at the start of a sentence, after a comma, or after "said",
    ///   "told me", "asked" and the like — closes by itself at the end of the
    ///   sentence. So does "open quote". "and I quote …" works the same way and
    ///   keeps its words, which is how people write it too.
    /// - Anywhere else a lone "quote" is the ordinary word and is left alone:
    ///   "get a quote from the contractor", "how about this quote Elias says".
    ///   Guessing there would put quotation marks where none were meant.
    ///
    /// Straight quotes, because they paste correctly into every app.
    public static func normalizeSpokenQuotes(_ text: String) -> String {
        var result = normalizeQuoteUnquote(text)
        let opener = "(and\\s+I\\s+quote|(?:open\\s+|begin\\s+)?quote)"
        // "quote-end quote" / "quote unquote" also closes a quote already open:
        // "Quote, that seems pretty good quote-end quote."
        let closer = "(?:quote[\\s,\\-]*)?(?:end\\s+(?:of\\s+)?quote|close\\s+quote|unquote)"

        // Paired: an opener, the quoted words, a closer. The words may run
        // across sentences but never past another "quote" — that is what let
        // "and I quote blah. … I quote, in quotes … end quote" swallow a whole
        // paragraph. The model often wraps the markers in commas ("said, quote,
        // I'll be there, end quote, and"), so a comma after the opener and
        // before the closer belongs to the markers; a sentence end just before
        // the closer ("do not enter. End quote.") stays with the quote.
        //
        // After the closer, American style: a period or comma moves inside the
        // quote; a question or exclamation mark stays outside, because it
        // belongs to the whole sentence ("Did he really say "yes"?").
        let span = "((?:(?!\\bquote\\b).)+?)"
        let paired = "(?i)(^|[.!?]\\s+)?\\b" + opener + "\\b[,:]?\\s+" + span + "([.!?])?,?\\s+\\b"
            + closer + "\\b([,.!?;]?)"
        result = replaceAll(paired, in: result) { g in
            let (lead, marker, quoted, inner, trailing) = (g[0], g[1], g[2], g[3], g[4])
            let moves = trailing == "." || trailing == ","
            let body = joinPunctuation(quoted + inner, moves ? trailing : "")
            let kept = prefix(for: marker)
            return lead + kept + "\"" + capitalized(body, if: g.startsSentence && kept.isEmpty)
                + "\"" + (moves ? "" : trailing)
        }

        // One character of a sentence: anything but a sentence end. A period
        // after a lone letter ("p.m.", "e.g.", "U.S.") or a title ("Dr.") is an
        // abbreviation, not an end.
        let unit = "(?:(?![.!?](?:\\s|$)).|(?<=\\b[A-Za-z])\\.|(?<=\\b(?:Mr|Mrs|Ms|Dr|St|vs|etc))\\.)"
        let sentenceEnd = "(?:((?<!\\b[A-Za-z])(?<!\\b(?:Mr|Mrs|Ms|Dr|St|vs|etc))\\.|[!?])(?=\\s|$)|$)"

        // Unpaired: an opener that plainly starts a quotation closes at the end
        // of the sentence, its punctuation inside. A bare "quote" counts only
        // where a quotation begins — sentence start, after a comma or colon, or
        // after a speech verb — and not before "me", "for", "from" and the like
        // ("quote me on that", "a quote for the roof").
        let speech = "(?:said|says|say|saying|wrote|writes|asked|asks|replied|replies|goes|went"
            + "|yelled|shouted|texted|told\\s+(?:me|us|him|her|them|you))"
        let bareLead = "(^|[.!?]\\s+|[,:;]\\s*|\\b" + speech + "\\s+)"
        // …and never straight into a closer: "quote, end quote" with nothing
        // between is the idiom, and quoting the words "end quote" is nonsense.
        let notOrdinary = "(?!(?:me|him|her|them|us|you|it|for|from|of|on|about|in"
            + "|end\\s+(?:of\\s+)?quote|close\\s+quote|unquote)\\b)"
        let unpaired = "(?i)(?:(^|[.!?]\\s+)?\\b(and\\s+I\\s+quote|open\\s+quote|begin\\s+quote)|"
            + bareLead + "(quote))\\b[,:]?\\s+" + notOrdinary + "(?!\")(" + unit + "+?)" + sentenceEnd
        result = replaceAll(unpaired, in: result) { g in
            // Either the explicit opener (groups 0-1) or the bare one (2-3) matched.
            let explicit = !g[1].isEmpty
            let lead = explicit ? g[0] : g[2]
            let marker = explicit ? g[1] : g[3]
            let (quoted, trailing) = (g[4], g[5])
            let startsSentence = lead.isEmpty ? g.matchStartsText : lead.trimmingCharacters(in: .whitespaces)
                .last.map { ".!?".contains($0) } ?? false
            let trimmed = quoted.trimmingCharacters(in: .whitespaces)
            let kept = prefix(for: marker)
            return lead + kept + "\""
                + capitalized(joinPunctuation(trimmed, trailing), if: startsSentence && kept.isEmpty) + "\""
        }
        return result
    }

    /// The "quote-unquote" idiom: scare quotes around what comes next.
    ///
    /// "it's a quote unquote big deal." → "it's a \"big deal.\"" The markers
    /// are said together (also "quote end quote", "quote-end quote"), so the
    /// only question is how far the quote runs. Up to the next punctuation if
    /// that is three words or fewer — "a quote unquote big deal." — otherwise
    /// just the next word: "a quote unquote expert on this topic" → "a
    /// \"expert\" on this topic". Said *after* a phrase ("pretty good, quote,
    /// end quote.") it is left as dictated: how many earlier words it covers
    /// can't be known, and guessing wrong is worse than doing nothing.
    static func normalizeQuoteUnquote(_ text: String) -> String {
        let idiom = "(?i)\\bquote[\\s,\\-]*(?:end[\\s\\-]+(?:of\\s+)?quote|close\\s+quote|unquote)\\b,?\\s+"
        let word = "[\\p{L}\\p{N}'’\\-]+"
        // Short phrase running to punctuation or the end, else one word. A
        // period or comma right after it goes inside, as everywhere else here.
        let short = "(" + word + "(?:\\s+" + word + "){0,2})(?:([.,])|(?=\\s*(?:[!?;:]|$)))"
        var result = replaceAll(idiom + short, in: text) { g in "\"" + g[0] + g[1] + "\"" }
        result = replaceAll(idiom + "(" + word + ")", in: result) { g in "\"" + g[0] + "\"" }
        return result
    }

    /// A quotation that opens a sentence starts with a capital, as in writing
    /// (not after a kept "And I quote," — the sentence already started):
    /// "Quote alliance is here." → "\"Alliance is here.\"". Mid-sentence it
    /// keeps the model's casing ("it's a \"big deal\"").
    private static func capitalized(_ text: String, if condition: Bool) -> String {
        guard condition, let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
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
        _ pattern: String, in text: String, with build: (Groups) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let values = (1..<match.numberOfRanges).map { i -> String in
                guard let r = Range(match.range(at: i), in: result) else { return "" }
                return String(result[r])
            }
            result.replaceSubrange(whole, with: build(Groups(values: values, matchStartsText: match.range.location == 0)))
        }
        return result
    }

    /// Capture groups of one match, plus whether the match began the text.
    private struct Groups {
        let values: [String]
        let matchStartsText: Bool
        subscript(i: Int) -> String { values[i] }

        /// For the paired pattern: its first group is the sentence start (or
        /// the start of the text) that precedes the opener, when there is one.
        var startsSentence: Bool { matchStartsText || !values[0].isEmpty }
    }
}
