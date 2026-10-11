import Foundation

/// A prompt that ends inside a word ("really appreci") makes a model see a word
/// boundary that is not there, and it starts a new word (mid-word hits 1–2/15
/// in the Phase 0 eval). Instead the partial word is taken off the prompt, and
/// a grammar forces the output to begin with it again (13–14/15). It also
/// covers a caret right after a complete word ("take your").
public enum TokenHealing {
    /// `prompt` ends on a token boundary; `forced` (the partial word with its
    /// leading space, if any) is what the output must start with. `forced` is
    /// empty when the caret is not in or after a word.
    public static func split(_ before: String) -> (prompt: String, forced: String) {
        let range = NSRange(before.startIndex..., in: before)
        guard let match = partialWord.firstMatch(in: before, range: range),
              let r = Range(match.range, in: before) else { return (before, "") }
        return (String(before[..<r.lowerBound]), String(before[r]))
    }

    /// A GBNF grammar for llama.cpp's grammar sampler: the forced start, then
    /// anything. The line is cut by the caller's newline stop, not here —
    /// forbidding "\n" made models run on, and a token like "\n@" fell off the
    /// grammar's end.
    public static func grammar(forcing forced: String) -> String? {
        guard !forced.isEmpty else { return nil }
        let literal = forced.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return #"root ::= ""# + literal + #"" ([^\n] | "\n")*"#
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
