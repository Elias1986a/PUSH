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

    /// The fix for the misspelled word at the caret, or the one just before
    /// it while the next word is being typed ("I will recieve i" → fix
    /// "recieve", keep " i"). `isTypo` is asked about a whole word;
    /// `isInProgress` says a partial word is the start of a real one
    /// ("apprec"), which is never a typo; `guesses` returns corrections best
    /// first.
    public static func find(in before: String,
                            isTypo: (String) -> Bool,
                            isInProgress: (String) -> Bool = { _ in false },
                            guesses: (String) -> [String]) -> TypoFix? {
        func trailingWord(_ text: Substring) -> String {
            String(text.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }.reversed())
        }
        func fix(_ word: String, trailing: String) -> TypoFix? {
            // Short words are too often deliberate ("ok", "hm"); capitalised
            // ones are usually names the checker doesn't know ("Priya").
            guard word.count >= 3, word.first?.isLowercase == true, isTypo(word) else { return nil }
            guard let guess = guesses(word).first(where: { candidate in
                !candidate.isEmpty && !candidate.contains(" ")
                    && candidate.lowercased() != word.lowercased()
            }) else { return nil }
            return TypoFix(typo: word, trailing: trailing, replacement: guess)
        }

        let text = Substring(before)
        // The word just finished with a space.
        if text.last == " " { return fix(trailingWord(text.dropLast()), trailing: " ") }

        // The word at the caret, unless it is still on its way to a real word.
        let partial = trailingWord(text)
        guard !partial.isEmpty else { return nil }
        if !isInProgress(partial), let atCaret = fix(partial, trailing: "") { return atCaret }

        // The word before it, while the next one is being typed.
        let rest = text.dropLast(partial.count)
        guard rest.last == " " else { return nil }
        return fix(trailingWord(rest.dropLast()), trailing: " " + partial)
    }
}
