/// The input line of a terminal, from the text up to its cursor.
///
/// An agent's prompt (Claude Code, Codex: a `>` or `❯` line under a rule of
/// box-drawing characters, sometimes inside a box) is prose, and Type treats
/// it like a chat field. A plain shell prompt is commands; Type stays out of
/// it unless the user turns it on.
public struct TerminalLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case agentPrompt, shell }

    public var kind: Kind
    /// What the user has typed on the line, prompt removed. Empty at an
    /// agent prompt not yet typed into: still a place Type works (its icon
    /// shows there, as Cotypist's does on any field it serves).
    public var text: String
    /// An agent prompt's conversation: the text above its rule, the last
    /// `contextLimit` characters, borders and blank lines removed.
    public var context: String?

    public static let contextLimit = 1_000
    /// How far up a wrapped prompt is looked for.
    static let maxPromptLines = 40

    public init(kind: Kind, text: String, context: String? = nil) {
        self.kind = kind
        self.text = text
        self.context = context
    }

    public static func parse(textBeforeCaret screen: String) -> TerminalLine? {
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let current = lines.last else { return nil }

        // An agent prompt: a `>` or `❯` line straight under a rule. Text that
        // wraps (or a Shift-Return) continues on the lines below it, so the
        // caret may be several lines down.
        for start in stride(from: lines.count - 1, through: max(1, lines.count - maxPromptLines), by: -1)
        where isRule(lines[start - 1]) {
            let first = unboxed(lines[start])
            // Continuation lines are indented under the prompt; a shell line is not.
            guard let marker = first.first, marker == ">" || marker == "❯",
                  lines[(start + 1)...].allSatisfy({ $0.isEmpty || " │┃".contains($0.first!) }) else { break }
            let pieces = [String(first.dropFirst())] + lines[(start + 1)...].map { String(unboxed($0)) }
            let text = pieces.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            let tail = current.last == " " && !text.isEmpty ? " " : ""
            return TerminalLine(kind: .agentPrompt, text: text + tail,
                                context: conversation(Array(lines[..<(start - 1)])))
        }
        // A shell prompt: everything up to the last "$ ", "% ", "❯ " or "> ".
        let markers = ["$ ", "% ", "❯ ", "> "]
        let ends = markers.compactMap { current.range(of: $0, options: .backwards)?.upperBound }
        guard let end = ends.max() else { return nil }
        let text = String(current[end...])
        return text.isEmpty ? nil : TerminalLine(kind: .shell, text: text)
    }

    /// The prompt's text after the cursor: the rest of its row and any rows
    /// below it, down to the rule that closes the prompt, without borders or
    /// padding. Nil when the cursor is at the end. Going back to fix a word
    /// left a suggestion drawn on top of the words after it (user photo,
    /// 2026-10-14); with this, it goes in a card below, as in other apps.
    public static func textAfterCaret(_ after: String?) -> String? {
        guard let after else { return nil }
        var pieces: [String] = []
        for line in after.split(separator: "\n", omittingEmptySubsequences: false) {
            if isRule(String(line)) { break }
            let text = line.filter { !"│┃".contains($0) }.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { pieces.append(text) }
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " ")
    }

    /// A line without a box's left border and the spaces after it.
    private static func unboxed(_ line: String) -> Substring {
        var line = Substring(line)
        if line.first == "│" || line.first == "┃" { line = line.dropFirst() }
        return line.drop { $0 == " " }
    }

    /// The agent's side of the conversation, as the model should read it.
    private static func conversation(_ lines: [String]) -> String? {
        var kept: [String] = []
        var count = 0
        for line in lines.reversed() {
            let text = line.filter { !"─━═╭╮╰╯┌┐└┘│┃".contains($0) }
                .trimmingCharacters(in: .whitespaces)
                .drop { "⏺●⎿".contains($0) }.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            kept.append(text)
            count += text.count + 1
            if count >= contextLimit { break }
        }
        let joined = kept.reversed().joined(separator: "\n")
        return joined.isEmpty ? nil : String(joined.suffix(contextLimit))
    }

    /// A horizontal rule of box-drawing characters (at least ten).
    static func isRule(_ line: String) -> Bool {
        line.filter { "─━═╭╮╰╯┌┐└┘".contains($0) }.count >= 10
    }
}
