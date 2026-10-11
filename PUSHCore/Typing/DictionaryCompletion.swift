import Foundation

/// Finishes a word from the user's PUSH Dictionary ("Kub" → "ernetes"),
/// without the model: the model has never seen the user's names and jargon,
/// and the Dictionary has.
public enum DictionaryCompletion {
    /// The words of the Dictionary's right-hand side ("Hamer", "Kubernetes";
    /// "New York" gives "New" and "York").
    public static func vocabulary(from terms: [String]) -> Set<String> {
        Set(terms.flatMap { $0.split { !($0.isLetter || $0 == "'" || $0 == "’" || $0 == "-") } }.map(String.init))
    }

    /// The rest of the one Dictionary word that `partial` begins, or nil.
    /// Only from the third letter, only when exactly one word fits, and never
    /// while `partial` is itself a real word: "Ham" is a word, so "Hamer" is
    /// offered from "Hame" — otherwise "the" would become "Theo" and push out
    /// the model's next-word suggestion.
    public static func complete(partial: String, vocabulary: Set<String>,
                                isRealWord: (String) -> Bool) -> String? {
        guard partial.count >= 3 else { return nil }
        let lower = partial.lowercased()
        let matches = Set(vocabulary.filter { $0.count > partial.count && $0.lowercased().hasPrefix(lower) }
            .map { $0.lowercased() })
        guard matches.count == 1, let match = matches.first,
              !vocabulary.contains(where: { $0.lowercased() == lower }), !isRealWord(partial),
              let word = vocabulary.first(where: { $0.lowercased() == match }) else { return nil }
        return String(word.dropFirst(partial.count))
    }
}
