import Foundation

/// When something the user copied is worth showing the model, and how much
/// of it. Copying is a strong hint of what is about to be written ("the
/// address is…"), but an old or unrelated clipboard only adds noise.
public enum ClipboardPolicy {
    /// Copied longer ago than this, it is probably not about this sentence.
    public static let freshness: TimeInterval = 5 * 60
    public static let maximumCharacters = 400
    /// Short copies (an address, a name, a number) are used even with no
    /// word in common with the text.
    static let shortCopy = 120

    public static func select(_ copied: String, copiedAt: Date, now: Date = Date(), before: String) -> String? {
        guard now.timeIntervalSince(copiedAt) <= freshness else { return nil }
        let text = TypingHistoryScrubber.scrub(copied).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, !text.contains(TypingHistoryScrubber.redaction) || text.count > 40 else { return nil }
        // Already in the text (copied from this very draft): nothing new.
        if before.contains(text.prefix(60)) { return nil }
        guard text.count <= shortCopy || sharesWord(text, String(before.suffix(600))) else { return nil }
        let clipped = text.count > maximumCharacters ? String(text.prefix(maximumCharacters)) + "…" : text
        return clipped.replacingOccurrences(of: "\n", with: " ")
    }

    /// A telling word (five letters or more) in both.
    static func sharesWord(_ a: String, _ b: String) -> Bool {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 5 })
        }
        return !words(a).isDisjoint(with: words(b))
    }
}
