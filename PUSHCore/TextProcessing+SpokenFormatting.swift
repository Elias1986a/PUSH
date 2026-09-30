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
    /// products is out"). A closing quote or bracket may sit between the
    /// punctuation and the command: `said, "It works." New paragraph.`
    private static let spokenLayout = try! NSRegularExpression(pattern:
        "(?i)(^|[.,;:!?][\"\u{201D}\u{2019})]?)\\s*\\b(new\\s*line|new\\s+paragraph|bullet\\s+point)\\b"
        + "(?!\\s+(?:of|for|to|in|on|at|from|with|by|is|was|are|were|has|had|will)\\b)"
        + "[.,;:!]?[ \\t]*")

    /// "Number one, …" at a break. The model writes small numbers as words
    /// and may write any as digits, so both count.
    private static let spokenListItem = try! NSRegularExpression(pattern:
        "(?i)(^|[.,;:!?][\"\u{201D}\u{2019})]?)\\s*\\bnumber\\s+(one|two|three|four|five|six|seven|eight|nine|ten|\\d{1,2})\\b"
        + "[.,;:!]?[ \\t]*")

    private static let listNumberWords = ["one", "two", "three", "four", "five",
                                          "six", "seven", "eight", "nine", "ten"]

    /// "Number one, milk. Number two, eggs." → "1. Milk" / "2. Eggs".
    ///
    /// Only a run that counts up from one, at least two long, becomes a list:
    /// "we're number one" or "number two on my list" is ordinary speech, and
    /// what separates a list from it is the next number arriving in order.
    private static func numberSpokenLists(_ text: String) -> String {
        let matches = spokenListItem.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let values: [Int] = matches.map { match in
            let word = (Range(match.range(at: 2), in: text).map { text[$0].lowercased() }) ?? ""
            return Int(word) ?? (listNumberWords.firstIndex(of: word).map { $0 + 1 } ?? 0)
        }

        // Runs of 1, 2, 3… in text order; everything else is left alone.
        var items: [(match: NSTextCheckingResult, number: Int)] = []
        var run: [(match: NSTextCheckingResult, number: Int)] = []
        for (match, value) in zip(matches, values) {
            if value == run.count + 1 {
                run.append((match, value))
            } else {
                if run.count >= 2 { items += run }
                run = value == 1 ? [(match, value)] : []
            }
        }
        if run.count >= 2 { items += run }
        guard !items.isEmpty else { return text }

        var result = text
        for (match, number) in items.reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let lead = Range(match.range(at: 1), in: result).map { String(result[$0]) } ?? ""
            let kept = lead == "," || lead == ";" ? "" : lead
            let replacement = kept + (match.range.location == 0 ? "" : "\n") + "\(number). "
            result.replaceSubrange(whole, with: replacement)
            capitalizeLetter(in: &result, at: result.index(whole.lowerBound, offsetBy: replacement.count))
        }
        return result
    }

    private static func capitalizeLetter(in text: inout String, at index: String.Index) {
        guard index < text.endIndex, text[index].isLowercase else { return }
        text.replaceSubrange(index...index, with: text[index].uppercased())
    }

    /// Turn spoken layout commands into line breaks and bullets.
    ///
    /// - "new line" → a line break, "new paragraph" → a blank line.
    /// - "bullet point" → a "- " item on its own line; the comma that separated
    ///   the items is dropped, and an item ends without a period, as lists do.
    /// - "number one, … number two, …" → "1. …" / "2. …" the same way, when the
    ///   numbers count up from one (`numberSpokenLists`).
    ///
    /// The punctuation in front of a break stays ("Hi John," / "Thanks,"), the
    /// command's own goes, and the next line starts with a capital, as it
    /// would if typed.
    ///
    /// Runs last in the chain: every earlier pass treats a newline as ordinary
    /// whitespace, and some collapse it.
    public static func applySpokenFormatting(_ text: String) -> String {
        var result = numberSpokenLists(text)
        let matches = spokenLayout.matches(in: result, range: NSRange(result.startIndex..., in: result))
        var hasListItems = result != text
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let commandRange = Range(match.range(at: 2), in: result) else { continue }
            let lead = Range(match.range(at: 1), in: result).map { String(result[$0]) } ?? ""
            let command = result[commandRange].lowercased()

            let replacement: String
            if command.hasPrefix("bullet") {
                hasListItems = true
                let kept = lead == "," || lead == ";" ? "" : lead
                replacement = kept + (match.range.location == 0 ? "" : "\n") + "- "
            } else if command.hasSuffix("paragraph") {
                replacement = lead + "\n\n"
            } else {
                replacement = lead + "\n"
            }
            result.replaceSubrange(whole, with: replacement)

            // The next line starts with a capital.
            capitalizeLetter(in: &result, at: result.index(whole.lowerBound, offsetBy: replacement.count))
        }

        guard hasListItems else { return result }
        // "- Bread." → "- Bread": an item that is one fragment loses its
        // period. One that holds whole sentences ("- Call Mom. She's waiting.")
        // keeps its punctuation.
        return result.components(separatedBy: "\n").map { line in
            guard let marker = line.range(of: "^(- |\\d+\\. )", options: .regularExpression),
                  line.hasSuffix(".") else { return line }
            let body = line[marker.upperBound...].dropLast()
            return body.range(of: "[.!?]\\s", options: .regularExpression) != nil ? line : String(line.dropLast())
        }.joined(separator: "\n")
    }
}
