import Foundation

/// Turns raw model output into what is shown, and tracks it as the user
/// accepts or types over it.
public enum SuggestionText {
    /// Labels from the prompt's preface. Seeing one means the model is echoing
    /// its context instead of continuing the user's text.
    private static let leak = try! NSRegularExpression(pattern: #"\b(Format|App|Title|Field|Domain|From|Style):"#)

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
            let start = i
            while i < line.endIndex, !line[i].isWhitespace { i = line.index(after: i) }
            end = i
            // Bare punctuation (", " before "everyone") is not a word.
            if line[start..<i].contains(where: { $0.isLetter || $0.isNumber }) { words += 1 }
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

    /// Wait for about three words (the user's call, 2026-10-10): on a blank
    /// page every model filled the gap with web text — forum introductions,
    /// markup, stories. A sign-off line counts, since the name comes next.
    /// Never with the caret parked inside a word ("hel|lo"), where a
    /// suggestion would splice into the letters after it (Cotabby's rule).
    static let minimumWords = 3

    public static func shouldSuggest(before: String, after: String?) -> Bool {
        let words = before.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
        guard words >= minimumWords || TypingPrompt.endsAtSignOff(before) else { return false }
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

    /// Text Type must never put in someone's mouth. Base models learned from
    /// raw web text, and on a near-empty page they reach for forum openings
    /// ("Hello, I'm a 17 year old girl"). Rejected: an invented self-introduction
    /// (age, gender, name), and explicit words the user did not type.
    public static func isUnwanted(_ suggestion: String, before: String) -> Bool {
        let lowerBefore = before.lowercased()
        let text = suggestion.lowercased()
        // Look across the join: "I'm a" may already be typed (accepted a word
        // at a time) with the age arriving now. Only a match that ends inside
        // the suggestion counts — what the user wrote alone is theirs.
        let tail = String(lowerBefore.suffix(40))
        let joined = tail + text
        let ns = joined as NSString
        for match in persona.matches(in: joined, range: NSRange(location: 0, length: ns.length))
        where match.range.location + match.range.length > (tail as NSString).length {
            return true
        }
        // Text that would state who the user is ("I am a | student of…",
        // "I'm from | …", "my name is | …"): only they know, a model invents.
        let beforeTail = NSRange(location: 0, length: (lowerBefore as NSString).length)
        if selfDescription.firstMatch(in: lowerBefore, range: beforeTail) != nil,
           text.contains(where: \.isLetter) { return true }
        // Closing punctuation right after a typed space ("Best " + ", regards"
        // would give "Best ,").
        if before.last == " " || before.last == "\t", let first = suggestion.first, ",.;:!?…".contains(first) {
            return true
        }
        // Forum and chat residue, or the model talking back about the prompt.
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^\[/?[a-z][a-z0-9 _-]{0,24}\]"#, options: .regularExpression) != nil { return true }
        if trimmed.components(separatedBy: " · ").count >= 3 { return true }
        if talkBack.contains(where: { trimmed.hasPrefix($0) || trimmed.contains(" " + $0) }) { return true }
        // Web-page debris (tags, @handles, links, template braces) unless the
        // user is writing that kind of thing already: base models learned
        // from raw pages ("Hello," → "<strong>@jason-m-smith</strong>").
        for (marker, family) in webMarkers where text.contains(marker) {
            if !family.contains(where: { lowerBefore.contains($0) }) { return true }
        }
        let words = Set(text.split { !$0.isLetter }.map(String.init))
        let typed = Set(lowerBefore.split { !$0.isLetter }.map(String.init))
        return !words.subtracting(typed).isDisjoint(with: explicit)
    }

    private static let persona = try! NSRegularExpression(pattern:
        #"\bmy name is\s+[a-z]|\b(i'?m|i am|im)\s+(a\s+)?(\d{1,2}([\s-]*(years?[\s-]*old|yo|y/o))?\b|(boy|girl|guy|woman|man|male|female|teen|teenager)\b)"#)

    /// The text ends where a fact about the writer would come next.
    private static let selfDescription = try! NSRegularExpression(pattern: [
        #"\b(i am|i'm|im) (a|an)\s*$"#,                                   // "I am a | student"
        #"\b(hi|hello|hey|hiya)[,!.]?\s+(i am|i'm|im)\s*$"#,              // "Hi, I'm | Sarah"
        #"\b(i am|i'm|im) from( the)?\s*$"#,                              // "I'm from | Manila"
        #"\bmy name is\s*$"#,
        #"\bi (work|study|live) (at|for|in)( an?| the)?\s*$"#,           // "I work at | …"
    ].joined(separator: "|"))

    /// A marker in a suggestion, and what in the user's own text makes it fine.
    private static let webMarkers: [(String, [String])] = [
        ("<", ["<"]), (">", ["<", ">"]), ("@", ["@"]), ("http", ["http", "www."]), ("://", ["://"]),
        ("www.", ["www.", "http"]), ("{", ["{"]), ("}", ["{", "}"]), ("[", ["["]),
    ]

    private static let talkBack = [
        "i'm not sure what you mean", "i am not sure what you mean", "as an ai", "as a language model",
        "i cannot help", "i can't help", "i don't understand the question",
    ]

    private static let explicit: Set<String> = [
        "sex", "sexy", "sexual", "porn", "porno", "nude", "nudes", "naked", "horny", "fuck", "fucking",
        "dick", "cock", "pussy", "boobs", "tits", "slut", "whore", "cum", "nsfw", "onlyfans",
    ]

    /// The model is looping or echoing (Cotabby suppresses "a short word
    /// sequence looping back to back" too):
    /// - it starts with the word just typed ("love to" + " to see you") —
    ///   also the mark of a field read a beat before the last keys landed;
    /// - a word repeats back to back ("3 3", "We We"), except the few that
    ///   genuinely double ("had had");
    /// - a short sequence loops three times;
    /// - it restarts the last four words the user wrote.
    public static func repeats(_ suggestion: String, before: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.lowercased().split(whereSeparator: \.isWhitespace)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }.filter { !$0.isEmpty }
        }
        let next = words(suggestion)
        guard let first = next.first else { return false }
        let startsNewWord = suggestion.first?.isWhitespace == true || before.last?.isWhitespace == true
        if startsNewWord, first == words(before).last { return true }
        if zip(next, next.dropFirst()).contains(where: { $0 == $1 && !legitimateDoubles.contains($0) }) {
            return true
        }
        // A one-to-three word sequence looping three times (". Hi S. Hi S. Hi S.").
        for period in 1...3 where next.count >= period * 3 {
            var run = 0
            for index in period..<next.count {
                run = next[index] == next[index - period] ? run + 1 : 0
                if run >= period * 2 { return true }
            }
        }
        // Restarting what was just written: the last four words before the
        // caret appear in the suggestion. Only the tail counts (Cotabby) — a
        // passage repeated elsewhere in a note is a fair thing to reproduce.
        let recent = words(String(before.suffix(120)))
        if recent.count >= 4, next.count >= 4 {
            let tail = Array(recent.suffix(4))
            for start in 0...(next.count - 4) {
                let run = Array(next[start..<start + 4])
                // The last word may be the half-typed one, finished in the copy
                // ("thanks for s" → "thanks for sending").
                if run.prefix(3) == tail.prefix(3), run[3].hasPrefix(tail[3]) { return true }
            }
        }
        return false
    }

    private static let legitimateDoubles: Set<String> = ["had", "that"]

    /// The last finished word before the caret, and the word being typed at
    /// it (nil when the caret follows a space or punctuation) — for the typo
    /// check: a suggestion built on "teh" continues a mistake.
    public static func caretWords(_ before: String) -> (finished: String?, partial: String?) {
        func isWordChar(_ c: Character) -> Bool { c.isLetter || c == "'" || c == "’" }
        let atWord = before.last.map(isWordChar) ?? false
        var words = before.split { !isWordChar($0) }.map(String.init)
        let partial = atWord ? words.popLast() : nil
        return (words.last, partial)
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

    /// "Space after the last word": accepting the end of a suggestion also
    /// types a space, so the next word can follow. Not when the suggestion
    /// already ends in one, nor mid-line, where text already follows the caret.
    public static func needsTrailingSpace(finishing suggestion: String, nextInField: Character?) -> Bool {
        guard let last = suggestion.last, !last.isWhitespace else { return false }
        return nextInField == nil || nextInField?.isNewline == true
    }
}
