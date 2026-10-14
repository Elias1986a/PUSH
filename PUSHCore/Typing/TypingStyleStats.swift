import Foundation

/// Numbers that describe how someone writes, for comparing how the user
/// types with how they talk in the learning assessment. Counts only: no
/// word or sentence of the text survives into the result.
public struct TypingStyleStats: Equatable, Sendable {
    public var texts = 0
    public var words = 0
    public var sentences = 0
    public var contractions = 0   // I'll, don't, it's…
    public var commas = 0
    public var exclamations = 0   // sentences ending in !
    public var questions = 0      // sentences ending in ?
    public var greetings = 0      // texts opening with hi/hey/hello/dear/good morning…
    public var letters = 0        // in words, for average word length

    public var wordsPerSentence: Double { sentences == 0 ? 0 : Double(words) / Double(sentences) }
    public var lettersPerWord: Double { words == 0 ? 0 : Double(letters) / Double(words) }
    public var contractionsPer100Words: Double { words == 0 ? 0 : Double(contractions) * 100 / Double(words) }
    public var commasPerSentence: Double { sentences == 0 ? 0 : Double(commas) / Double(sentences) }
    public var exclamationShare: Double { sentences == 0 ? 0 : Double(exclamations) / Double(sentences) }
    public var questionShare: Double { sentences == 0 ? 0 : Double(questions) / Double(sentences) }
    public var greetingShare: Double { texts == 0 ? 0 : Double(greetings) / Double(texts) }

    private static let greetingStarts = ["hi ", "hi,", "hey", "hello", "dear ", "good morning", "good afternoon", "morning", "yo "]

    public static func measure(_ texts: [String]) -> TypingStyleStats {
        var s = TypingStyleStats()
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            s.texts += 1
            let lower = trimmed.lowercased()
            if greetingStarts.contains(where: { lower.hasPrefix($0) }) { s.greetings += 1 }
            s.commas += trimmed.filter { $0 == "," }.count
            trimmed.enumerateSubstrings(in: trimmed.startIndex..., options: .bySentences) { sentence, _, _, _ in
                guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
                s.sentences += 1
                if sentence.hasSuffix("!") { s.exclamations += 1 }
                if sentence.hasSuffix("?") { s.questions += 1 }
            }
            trimmed.enumerateSubstrings(in: trimmed.startIndex..., options: .byWords) { word, _, _, _ in
                guard let word else { return }
                s.words += 1
                s.letters += word.filter(\.isLetter).count
                if word.contains("'") || word.contains("’") { s.contractions += 1 }
            }
        }
        return s
    }
}
