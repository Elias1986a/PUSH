import Foundation

/// A prompt that ends inside a word ("really appreci") makes a model see a word
/// boundary that is not there, and it starts a new word (mid-word hits 1–2/15
/// in the Phase 0 eval). Instead the partial word is taken off the prompt, and
/// a grammar forces the output to begin with it again (13–14/15). It also
/// covers a caret right after a complete word ("take your").
public enum TokenHealing {
    /// `prompt` ends on a token boundary; `forced` (the partial word with its
    /// leading space, or the trailing spaces) is what the output must start
    /// with. `forced` is empty after punctuation or a newline.
    public static func split(_ before: String) -> (prompt: String, forced: String) {
        // Trailing spaces too: " see" is one token, so a prompt ending in a
        // bare space made the model predict a line break instead of a word.
        let spaces = before.reversed().prefix { $0 == " " || $0 == "\t" }
        if !spaces.isEmpty, spaces.count < before.count {
            return (String(before.dropLast(spaces.count)), String(spaces))
        }
        let range = NSRange(before.startIndex..., in: before)
        guard let match = partialWord.firstMatch(in: before, range: range),
              let r = Range(match.range, in: before) else { return (before, "") }
        return (String(before[..<r.lowerBound]), String(before[r]))
    }

    /// A GBNF grammar for llama.cpp's grammar sampler: the forced start, then
    /// anything. The line is cut by the caller's newline stop, not here —
    /// forbidding "\n" made models run on, and a token like "\n@" fell off the
    /// grammar's end.
    /// `wordBoundary`: the word is finished — the next character is a space
    /// or punctuation. Used when the model glued letters onto a complete word
    /// ("Hello" + "u").
    public static func grammar(forcing forced: String, wordBoundary: Bool = false) -> String? {
        guard !forced.isEmpty else { return nil }
        let literal = forced.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // A space or punctuation — not "any non-letter", which let a model
        // switch to Chinese characters right after an English word.
        // (No "-": llama.cpp's grammar parser rejects an escaped hyphen.)
        let boundary = wordBoundary ? #" [ ,.!?;:'"’)]"# : ""
        return #"root ::= ""# + literal + #"""# + boundary + #" ([^\n] | "\n")*"#
    }

    /// The word formed when a continuation glues letters straight onto the
    /// partial word ("appreci" + "ate" = "appreciate"), or nil when it starts
    /// with a space or punctuation. The app checks it with the spell checker.
    public static func gluedWord(forced: String, continuation: String) -> String? {
        let partial = forced.trimmingCharacters(in: .whitespaces)
        let letters = continuation.prefix { $0.isLetter || $0 == "'" || $0 == "’" }
        guard !partial.isEmpty, !letters.isEmpty else { return nil }
        return partial + letters
    }

    /// The output with the forced start removed, or nil if it does not begin
    /// with it (the grammar should make that impossible).
    public static func strip(_ output: String, forced: String) -> String? {
        guard output.hasPrefix(forced) else { return nil }
        return String(output.dropFirst(forced.count))
    }

    // An optional space or tab (never a newline: it would land inside the
    // grammar's string), then a word: a letter or digit, then letters, digits,
    // apostrophes. Anchored at the end of the text.
    private static let partialWord = try! NSRegularExpression(pattern: #"[ \t]?[^\W_][\w'’]*$"#)
}
