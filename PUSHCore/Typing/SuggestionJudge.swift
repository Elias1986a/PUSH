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
    /// Set once the glued-word question is settled (or never arises).
    private var judged: Bool

    public init(forced: String, before: String, length: LengthPreset, wordBoundary: Bool,
                isRealWord: @escaping (String) -> Bool) {
        self.forced = forced
        self.before = before
        self.length = length
        self.isRealWord = isRealWord
        self.judged = wordBoundary || forced.isEmpty
    }

    /// `raw`: everything streamed so far, forced start included. `final`:
    /// the stream has ended.
    public mutating func judge(_ raw: String, final: Bool) -> Verdict {
        guard let text = TokenHealing.strip(raw, forced: forced) else { return .wait }
        if !judged {
            if let word = TokenHealing.gluedWord(forced: forced, continuation: text) {
                let wordEnded = text.contains { !($0.isLetter || $0 == "'" || $0 == "’") }
                guard wordEnded || final else { return .wait }     // wait for the whole word
                judged = true
                if !isRealWord(word) { return .retryWithBoundary }
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
        if !SuggestionText.matchesScript(polished, before: before) { return .reject("other writing system") }
        if SuggestionText.isUnwanted(polished, before: before) { return .reject("unwanted content") }
        if SuggestionText.repeats(polished, before: before) { return .reject("repeats or loops") }
        return .show(polished)
    }
}
