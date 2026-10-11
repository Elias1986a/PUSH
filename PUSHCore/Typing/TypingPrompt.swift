import Foundation

/// Everything known about where the user is typing. Only `before` is required.
public struct TypingContext: Sendable, Equatable {
    public var before: String
    public var after: String?
    public var surfaceLine: String?
    public var style: String?
    public var language: String?
    public var userName: String?
    public var clipboard: String?
    public var screen: String?
    public var examples: [String]

    public init(before: String, after: String? = nil, surfaceLine: String? = nil, style: String? = nil,
                language: String? = nil, userName: String? = nil, clipboard: String? = nil,
                screen: String? = nil, examples: [String] = []) {
        self.before = before
        self.after = after
        self.surfaceLine = surfaceLine
        self.style = style
        self.language = language
        self.userName = userName
        self.clipboard = clipboard
        self.screen = screen
        self.examples = examples
    }
}

/// Builds the prompt for a base model: a short preface of context lines, a
/// blank line, then the text before the caret as the very last bytes, so the
/// model simply continues it. No instructions — a base model only continues.
public enum TypingPrompt {
    /// Room for the whole caret window (4,000) plus the preface, so the
    /// window is never cut again here (a cut would slide with every key).
    public static let defaultBudget = 6_000
    /// However small the budget, the caret text keeps this many characters.
    static let beforeFloor = 1_000
    static let afterCap = 200

    public static func render(_ context: TypingContext, budget: Int = defaultBudget) -> String {
        let total = max(budget, beforeFloor)
        // The caret text has top priority, so it is fitted first and on its own.
        let before = String(context.before.suffix(total))
        // What is left, less the blank line that separates preface and caret text.
        let room = total - before.count - 2
        let preface = room > 0 ? PromptBudget.fit(prefaceSections(context), total: room) : []
        guard !preface.isEmpty else { return before }
        return preface.map(\.text).joined(separator: "\n") + "\n\n" + before
    }

    /// In the order they appear; `PromptBudget` fills them by priority.
    static func prefaceSections(_ c: TypingContext) -> [PromptBudget.Section] {
        var s: [PromptBudget.Section] = []
        func add(_ name: String, _ text: String?, _ priority: Int, allOrNothing: Bool = false) {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            s.append(.init(name: name, text: text, priority: priority, keep: .start, allOrNothing: allOrNothing))
        }
        add("surface", c.surfaceLine, 70)
        // Only at a sign-off: anywhere else small models kept inserting the name.
        add("name", endsAtSignOff(c.before) ? c.userName.map { "From: \($0)." } : nil, 60)
        add("style", c.style.map { "Style: \($0)" }, 55)
        add("language", c.language.map { "Language: \($0)." }, 50)
        add("screen", c.screen.map { "On screen:\n\($0)" }, 45)
        add("clipboard", c.clipboard.map { "Copied: \($0)" }, 35)
        add("examples", c.examples.isEmpty ? nil
            : "How I write:\n" + c.examples.map { "- \($0)" }.joined(separator: "\n"), 38, allOrNothing: true)
        add("after", c.after.map { "Later in the same passage:\n“\($0.prefix(afterCap))”" }, 80, allOrNothing: true)
        return s
    }

    private static let signOff = try! NSRegularExpression(
        pattern: #"(?:^|\s)(?:thanks|thank you|best|cheers|regards),[ \t]*\n?$"#,
        options: [.caseInsensitive])

    static func endsAtSignOff(_ before: String) -> Bool {
        let tail = String(before.suffix(40))
        return signOff.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)) != nil
    }
}
