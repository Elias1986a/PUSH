import Foundation

/// "no" written where "know" was said.
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - "no" → "know"

    /// Negated auxiliaries. "Don't no" cannot be the word no: these need a verb
    /// after them, and the speaker's own "I don't, no" has a comma between.
    private static let knowNegatedAuxiliaries: Set<String> = [
        "don't", "doesn't", "didn't", "won't", "wouldn't",
        "couldn't", "shouldn't", "can't", "cannot"
    ]

    /// Openers of a yes/no question: "do you no where", "didn't they no".
    private static let knowQuestionAuxiliaries: Set<String> = [
        "do", "did", "does", "don't", "doesn't", "didn't"
    ]

    private static let knowSubjects: Set<String> = ["i", "you", "we", "they", "he", "she"]
    private static let knowObjects: Set<String> = ["me", "us", "you", "him", "her", "them"]

    /// Words that keep a real "no" alive even where a verb is expected:
    /// "didn't no one tell you", "I no longer", "to no avail", "do you no longer".
    private static let knowBlockers: Set<String> = [
        "one", "longer", "more", "matter", "doubt", "less", "sooner", "way",
        "end", "avail", "problem", "thanks", "body", "idea", "sir", "ma'am"
    ]

    /// What follows "know" and cannot follow a bare "no" after a subject:
    /// "I no what", "we no that", "they no him".
    private static let knowComplements: Set<String> = [
        "what", "that", "how", "why", "where", "when", "who", "whom", "whose",
        "whether", "if", "about", "it", "him", "her", "them", "me", "you", "us",
        "this", "these", "those", "the", "a", "an", "anything", "everything",
        "everyone", "everybody", "someone", "somebody", "something", "exactly"
    ]

    /// After "to", only the question words: "want to no why". "To no one",
    /// "to no avail" and "to no end" are the word no.
    private static let knowAfterTo: Set<String> = [
        "what", "how", "why", "where", "when", "who", "whether", "if", "about"
    ]

    /// Verbs that make "you" their object, after which "no" is a real answer:
    /// "I told you no if you asked", "give you no reason".
    private static let knowVerbsTakingYou: Set<String> = [
        "tell", "told", "tells", "telling", "say", "said", "says",
        "ask", "asked", "give", "gave", "gives", "giving",
        "show", "showed", "shows", "offer", "offered", "send", "sent",
        "owe", "owed", "leave", "left", "wish", "get", "got", "answer", "answered"
    ]

    /// Where "you no," can only be the filler "you know,": at the start of a
    /// clause. "I told you no, but" has a verb before it instead.
    private static let knowClauseOpeners: Set<String> = [
        "but", "and", "so", "or", "because", "cause", "'cause"
    ]

    /// Turn "no" into "know" where the words around it leave no other reading.
    ///
    /// Only the shapes where "no" cannot be the word no: after a negated
    /// auxiliary ("I don't no"), inside "let me no", in a question ("do you no
    /// where"), after a subject when what follows needs a verb ("I no what you
    /// mean"), after "to" before a question word, and the clause-opening filler
    /// "you no,". Anything that reads both ways is left as the engine wrote it:
    /// "but no, I'm frustrated" is a sentence either way, and only the audio
    /// knows which one was said.
    public static func fixNoMeaningKnow(_ text: String) -> String {
        guard text.range(of: "no", options: .caseInsensitive) != nil,
              let tokenRegex = try? NSRegularExpression(
                // A word (letters, inner apostrophes) or one punctuation mark.
                pattern: "\\p{L}(?:[\\p{L}\\p{N}_'\u{2019}]*\\p{L})?|\\S"
              ) else { return text }

        let ns = text as NSString
        let tokens = tokenRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { $0.range }
        func word(_ i: Int) -> String? {
            guard tokens.indices.contains(i) else { return nil }
            let t = ns.substring(with: tokens[i])
            guard t.first?.isLetter == true else { return nil }
            return t.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        }

        let out = NSMutableString(string: text)
        // Last to first, so earlier ranges stay valid as lengths change.
        for i in tokens.indices.reversed() where word(i) == "no" {
            let previous = word(i - 1)
            // A punctuation mark between the two words ends the context.
            let beforePrevious = previous == nil ? nil : word(i - 2)
            let next = word(i + 1)
            let nextMark = next == nil && tokens.indices.contains(i + 1)
                ? ns.substring(with: tokens[i + 1]) : nil
            // "no-show", "yes/no".
            if let mark = nextMark, "-\u{2013}\u{2014}/".contains(mark) { continue }
            let unblocked = next.map { !knowBlockers.contains($0) } ?? true

            let meansKnow: Bool
            if let p = previous, knowNegatedAuxiliaries.contains(p) {
                meansKnow = unblocked
            } else if beforePrevious == "let", let p = previous, knowObjects.contains(p) {
                meansKnow = unblocked
            } else if let b = beforePrevious, knowQuestionAuxiliaries.contains(b),
                      let p = previous, knowSubjects.contains(p) {
                meansKnow = unblocked
            } else if let p = previous, ["i", "we", "they"].contains(p) {
                meansKnow = next.map { knowComplements.contains($0) } ?? false
            } else if previous == "you" {
                let complement = (next.map { knowComplements.contains($0) } ?? false)
                    && !(beforePrevious.map { knowVerbsTakingYou.contains($0) } ?? false)
                let filler = nextMark == ","
                    && (beforePrevious.map { knowClauseOpeners.contains($0) } ?? true)
                meansKnow = complement || filler
            } else if previous == "to" {
                meansKnow = next.map { knowAfterTo.contains($0) } ?? false
            } else {
                meansKnow = false
            }
            guard meansKnow else { continue }

            let written = ns.substring(with: tokens[i])
            let replacement = written == "NO" ? "KNOW" : written.hasPrefix("N") ? "Know" : "know"
            out.replaceCharacters(in: tokens[i], with: replacement)
        }
        return out as String
    }
}
