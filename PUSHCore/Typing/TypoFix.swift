import Foundation

/// A misspelled word just before the caret and the word to put in its place.
/// Offered instead of a continuation: the accept key deletes the typo (and the
/// space typed after it) and types the fix. Pure, with the spell checker
/// passed in, so it is pinned by tests. The idea of offering one native
/// correction for the word at the caret, rather than going quiet, is
/// Cotabby's (its typo gate); the code is ours.
public struct TypoFix: Equatable, Sendable {
    /// The word as typed.
    public let typo: String
    /// What follows it before the caret: nothing, or the one space that
    /// finished it.
    public let trailing: String
    /// The correction, in the typo's capitalisation.
    public let replacement: String

    /// Characters to delete before typing `typed`.
    public var deleteCount: Int { typo.count + trailing.count }
    /// What goes back in their place.
    public var typed: String { replacement + trailing }

    /// The fix for the word at the end of `before`, if it is misspelled and
    /// the checker has a one-word correction. `isTypo` is asked about the
    /// whole word; `guesses` returns corrections best first.
    public static func find(in before: String,
                            isTypo: (String) -> Bool,
                            guesses: (String) -> [String]) -> TypoFix? {
        var text = Substring(before)
        var trailing = ""
        if text.last == " " {
            trailing = " "
            text = text.dropLast()
        }
        let word = String(text.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }.reversed())
        // Short words are too often deliberate ("ok", "hm"); capitalised ones
        // are usually names the checker doesn't know ("Priya").
        guard word.count >= 3, word.first?.isLowercase == true, isTypo(word) else { return nil }
        guard let guess = guesses(word).first(where: { candidate in
            !candidate.isEmpty && !candidate.contains(" ")
                && candidate.lowercased() != word.lowercased()
        }) else { return nil }
        return TypoFix(typo: word, trailing: trailing, replacement: guess)
    }
}
