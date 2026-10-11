import Foundation

/// Turns raw model output into what is shown, and tracks it as the user
/// accepts or types over it.
public enum SuggestionText {
    /// Labels from the prompt's preface. Seeing one means the model is echoing
    /// its context instead of continuing the user's text.
    private static let leak = try! NSRegularExpression(pattern: #"\b(Format|App|Title|Field|Domain|From):"#)

    /// First line only, at most `maxWords` words, trailing space trimmed. The
    /// leading space is the model's and is kept: it says whether the text
    /// continues the current word or starts a new one. Nil when nothing worth
    /// showing is left.
    public static func clean(_ raw: String, maxWords: Int) -> String? {
        let line = raw.prefix { $0 != "\n" && $0 != "\r" }
        var end = line.startIndex
        var words = 0
        var i = line.startIndex
        while i < line.endIndex, words < maxWords {
            while i < line.endIndex, line[i].isWhitespace { i = line.index(after: i) }
            guard i < line.endIndex else { break }
            while i < line.endIndex, !line[i].isWhitespace { i = line.index(after: i) }
            end = i
            words += 1
        }
        let text = String(line[..<end])
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        guard leak.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil else { return nil }
        return text
    }

    /// What one press of the next-word key types: leading space plus the
    /// first word with any punctuation attached to it.
    public static func nextChunk(of suggestion: String) -> String {
        let spaces = suggestion.prefix { $0.isWhitespace }
        let word = suggestion.dropFirst(spaces.count).prefix { !$0.isWhitespace }
        return String(spaces + word)
    }

    /// What is still worth showing after the user typed `typed` themselves
    /// while `suggestion` was up. Nil when they typed something else, or typed
    /// all of it.
    public static func remainder(of suggestion: String, afterTyping typed: String) -> String? {
        guard suggestion.hasPrefix(typed) else { return nil }
        let rest = String(suggestion.dropFirst(typed.count))
        return rest.isEmpty ? nil : rest
    }
}
