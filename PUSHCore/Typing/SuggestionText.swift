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

    /// Fixes what a small model gets wrong about the text it continues:
    /// capitalises the first word of a new sentence, and rejects a capital
    /// glued onto the word at the caret ("hello" + "World"). The sentence
    /// rule needs whitespace between the stop and the word, so "3." + "5" is
    /// a decimal, not a new sentence.
    public static func polish(_ suggestion: String, before: String) -> String? {
        guard let first = suggestion.first(where: { !$0.isWhitespace }) else { return suggestion }
        if let last = before.last, last.isLetter, last.isLowercase, suggestion.first?.isUppercase == true {
            return nil
        }
        let trimmedBefore = before.reversed().drop { $0.isWhitespace }
        let spaced = before.last?.isWhitespace == true || suggestion.first?.isWhitespace == true
        guard spaced, let stop = trimmedBefore.first, ".!?".contains(stop), first.isLowercase,
              let index = suggestion.firstIndex(of: first) else { return suggestion }
        return suggestion.replacingCharacters(in: index...index, with: String(first).uppercased())
    }

    /// Any typed text is enough — a first word gets the model's ordinary
    /// guess at how a sentence goes on (Cotabby's rule too). The exception is
    /// a caret parked inside a word ("hel|lo"), where a suggestion would
    /// splice into the letters after it.
    public static func shouldSuggest(before: String, after: String?) -> Bool {
        guard before.contains(where: { !$0.isWhitespace }) else { return false }
        if let last = before.last, isWordCharacter(last),
           let next = after?.first, isWordCharacter(next) { return false }
        return true
    }

    private static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "'" || c == "’" }

    /// Every letter in the suggestion is in a writing system the text already
    /// uses. Small multilingual models (Qwen especially) drift into Chinese,
    /// Japanese or Korean when there is little context; that output is
    /// rejected. Text with no letters yet counts as Latin.
    public static func matchesScript(_ suggestion: String, before: String) -> Bool {
        var allowed = Set(before.unicodeScalars.compactMap(script))
        if allowed.isEmpty { allowed = [.latin] }
        return suggestion.unicodeScalars.allSatisfy { scalar in script(scalar).map(allowed.contains) ?? true }
    }

    enum Script { case latin, greek, cyrillic, hebrew, arabic, devanagari, thai, hangul, cjk, other }

    /// The writing system of a letter; nil for anything that is not a letter.
    static func script(_ scalar: Unicode.Scalar) -> Script? {
        guard scalar.properties.isAlphabetic else { return nil }
        switch scalar.value {
        case 0x0041...0x024F, 0x1E00...0x1EFF: return .latin
        case 0x0370...0x03FF: return .greek
        case 0x0400...0x052F: return .cyrillic
        case 0x0590...0x05FF: return .hebrew
        case 0x0600...0x06FF, 0x0750...0x077F: return .arabic
        case 0x0900...0x097F: return .devanagari
        case 0x0E00...0x0E7F: return .thai
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return .hangul
        // Kana and Han together: Japanese mixes them, Chinese uses Han.
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: return .cjk
        default: return .other
        }
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
