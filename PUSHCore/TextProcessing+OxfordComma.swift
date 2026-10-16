import Foundation
import NaturalLanguage

/// The Oxford comma.
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - Oxford comma

    /// First words of an opening that ends in a comma without starting a list:
    /// a greeting or interjection ("Hi John, Mary and I…"), a sentence adverb
    /// ("Honestly, I think…"), or a subordinate or prepositional opening
    /// ("When I got home, Sarah and I…", "After the meeting, John and…").
    private static let oxfordOpeners: Set<String> = [
        "hi", "hey", "hello", "dear", "thanks", "thank", "please", "sorry",
        "yes", "yeah", "yep", "no", "nope", "ok", "okay", "oh", "well", "so", "sure", "right", "alright",
        "wow", "um", "uh", "look", "listen", "anyway", "also", "plus", "now", "then",
        "honestly", "basically", "actually", "obviously", "seriously", "personally", "frankly",
        "unfortunately", "fortunately", "luckily", "hopefully", "apparently", "literally", "first", "finally",
        "when", "whenever", "if", "unless", "after", "before", "because", "since", "while", "although",
        "though", "once", "as", "until", "in", "on", "at", "during", "for", "with", "without", "by", "from",
    ]

    /// Greetings that can take a comma before the name as well as after it.
    private static let oxfordGreetings: Set<String> = ["hi", "hey", "hello", "dear", "thanks", "morning", "evening"]

    /// After "and": a subject pronoun means a compound subject ("Sarah and I
    /// talked"), not the last item of a list.
    private static let oxfordSubjects: Set<String> = ["i", "we", "he", "she", "they", "you"]

    /// Words that make the stretch before "and" a clause, not a list item.
    private static let oxfordClauseWords: Set<String> = [
        "and", "or", "but", "so", "because", "yet", "although", "though", "while", "which", "that",
    ]

    /// "milk, eggs and bread" → "milk, eggs, and bread". Only where a comma
    /// already marks the list in the same sentence, the last item before the
    /// conjunction is short and has no verb, and the comma isn't closing a
    /// greeting or an opening phrase.
    public static func addOxfordComma(_ text: String) -> String {
        guard text.contains(","),
              text.range(of: #"\b(and|or)\b"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            return text
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var verbs: [Range<String.Index>] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            if tag == .verb { verbs.append(range) }
            return true
        }

        var insertions: [String.Index] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { _, sentence, _, _ in
            let tokens = text[sentence].split(whereSeparator: \.isWhitespace)
            func bare(_ k: Int) -> String {
                tokens[k].lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            }
            guard let firstComma = tokens.firstIndex(where: { $0.hasSuffix(",") }) else { return }
            for j in tokens.indices where j > 0 {
                let conjunction = String(tokens[j]).lowercased()
                guard conjunction == "and" || conjunction == "or", !tokens[j - 1].hasSuffix(",") else { continue }
                guard let k = tokens[..<j].lastIndex(where: { $0.hasSuffix(",") }) else { continue }
                // The last item: one to five words, no verb, nothing that starts a clause.
                let item = (k + 1)..<j
                guard (1...5).contains(item.count),
                      !item.contains(where: { oxfordClauseWords.contains(bare($0)) }),
                      !verbs.contains(where: { $0.overlaps(tokens[item.lowerBound].startIndex..<tokens[item.upperBound - 1].endIndex) })
                else { continue }
                if k == firstComma, oxfordOpeners.contains(bare(tokens.startIndex)) { continue }
                // "Hi, John, Mary and Sarah…": a greeting's own comma comes
                // before the name, so the comma after the name closes it too.
                if oxfordGreetings.contains(bare(tokens.startIndex)), tokens.startIndex == firstComma,
                   k == tokens[(firstComma + 1)...].firstIndex(where: { $0.hasSuffix(",") }) { continue }
                if j + 1 < tokens.endIndex, oxfordSubjects.contains(bare(j + 1)) { continue }
                insertions.append(tokens[j - 1].endIndex)
            }
        }

        var out = text
        for index in insertions.sorted(by: >) { out.insert(",", at: index) }
        return out
    }
}
