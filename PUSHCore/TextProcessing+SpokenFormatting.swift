import Foundation

/// Spoken layout commands — "new line", "new paragraph", "bullet point".
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - Spoken formatting

    /// A command only where a break can go: at the start of the take or right
    /// after punctuation, which the model writes wherever you pause — "Hi John,
    /// new line, thanks" or "Groceries: bullet point milk". Mid-phrase the words
    /// are the ordinary noun ("we launched a new line of shoes"), and so they
    /// are before a preposition or verb even after a comma ("Okay, new line of
    /// products is out").
    private static let spokenLayout = try! NSRegularExpression(pattern:
        "(?i)(^|[.,;:!?])\\s*\\b(new\\s*line|new\\s+paragraph|bullet\\s+point)\\b"
        + "(?!\\s+(?:of|for|to|in|on|at|from|with|by|is|was|are|were|has|had|will)\\b)"
        + "[.,;:!]?[ \\t]*")

    /// Turn spoken layout commands into line breaks and bullets.
    ///
    /// - "new line" → a line break, "new paragraph" → a blank line.
    /// - "bullet point" → a "- " item on its own line; the comma that separated
    ///   the items is dropped, and an item ends without a period, as lists do.
    ///
    /// The punctuation in front of a break stays ("Hi John," / "Thanks,"), the
    /// command's own goes, and the next line starts with a capital, as it
    /// would if typed.
    ///
    /// Runs last in the chain: every earlier pass treats a newline as ordinary
    /// whitespace, and some collapse it.
    public static func applySpokenFormatting(_ text: String) -> String {
        let matches = spokenLayout.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        var hasBullets = false
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let commandRange = Range(match.range(at: 2), in: result) else { continue }
            let lead = Range(match.range(at: 1), in: result).map { String(result[$0]) } ?? ""
            let command = result[commandRange].lowercased()

            let replacement: String
            if command.hasPrefix("bullet") {
                hasBullets = true
                let kept = lead == "," || lead == ";" ? "" : lead
                replacement = kept + (match.range.location == 0 ? "" : "\n") + "- "
            } else if command.hasSuffix("paragraph") {
                replacement = lead + "\n\n"
            } else {
                replacement = lead + "\n"
            }
            result.replaceSubrange(whole, with: replacement)

            // The next line starts with a capital.
            let after = result.index(whole.lowerBound, offsetBy: replacement.count)
            if after < result.endIndex, result[after].isLowercase {
                result.replaceSubrange(after...after, with: result[after].uppercased())
            }
        }

        guard hasBullets else { return result }
        // "- Bread." → "- Bread": an item that is one fragment loses its
        // period. One that holds whole sentences ("- Call Mom. She's waiting.")
        // keeps its punctuation.
        return result.components(separatedBy: "\n").map { line in
            guard line.hasPrefix("- "), line.hasSuffix(".") else { return line }
            let body = line.dropLast()
            return body.range(of: "[.!?]\\s", options: .regularExpression) != nil ? line : String(body)
        }.joined(separator: "\n")
    }
}
