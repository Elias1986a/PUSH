import Foundation

/// Decides what to do with the model's output so far — the one place the
/// app and the replay eval share, so the eval measures exactly what users see.
public struct SuggestionJudge {
    public enum Verdict: Equatable {
        /// Nothing worth showing yet; keep streaming.
        case wait
        case show(String)
        /// Unacceptable: take down anything shown and stop.
        case reject(String)
        /// The model glued letters onto a finished word ("Hello" + "u"): ask
        /// again with a word break forced after it.
        case retryWithBoundary
    }

    let forced: String
    let before: String
    let length: LengthPreset
    let isRealWord: (String) -> Bool
    /// Text the user can see besides `before` (screen, clipboard): numbers in
    /// it are theirs, not the model's guesses.
    let known: String
    /// Set once the glued-word question is settled (or never arises).
    private var judged: Bool

    public init(forced: String, before: String, length: LengthPreset, wordBoundary: Bool, known: String = "",
                isRealWord: @escaping (String) -> Bool) {
        self.forced = forced
        self.before = before
        self.length = length
        self.isRealWord = isRealWord
        self.known = known
        self.judged = wordBoundary || forced.isEmpty
    }

    /// `raw`: everything streamed so far, forced start included. `final`:
    /// the stream has ended.
    public mutating func judge(_ raw: String, final: Bool) -> Verdict {
        guard var text = TokenHealing.strip(raw, forced: forced) else { return .wait }
        // The space after a finished sentence is not in the field: it is shown.
        if TokenHealing.addsSpace(before) { text = forced + text }
        if !judged {
            if let word = TokenHealing.gluedWord(forced: forced, continuation: text) {
                let wordEnded = text.contains { !($0.isLetter || $0 == "'" || $0 == "’") }
                if wordEnded || final {
                    judged = true
                    if !isRealWord(word) { return .retryWithBoundary }
                } else if !isRealWord(word) {
                    return .wait     // "appreci" + "at": wait for the whole word
                }
                // Already a word ("congr" + "atulations"): show it now, a model
                // step sooner, and judge again once the word ends.
            } else {
                judged = true
            }
        }
        guard let clean = SuggestionText.clean(text, maxWords: length.words.upperBound) else {
            return final ? .reject("empty after cleanup") : .wait
        }
        guard let polished = SuggestionText.polish(length.trim(clean), before: before) else {
            return .reject("capital glued onto the word")
        }
        let year = Calendar.current.component(.year, from: Date())
        guard let polished = SuggestionText.cutAtNewNumber(polished, before: before, known: known, year: year) else {
            return .reject("a number the user never wrote")
        }
        if !SuggestionText.matchesScript(polished, before: before) { return .reject("other writing system") }
        if SuggestionText.isUnwanted(polished, before: before) { return .reject("unwanted content") }
        if SuggestionText.repeats(polished, before: before) { return .reject("repeats or loops") }
        return .show(polished)
    }
}
