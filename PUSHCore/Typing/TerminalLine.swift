/// The input line of a terminal, from the text up to its cursor.
///
/// An agent's prompt (Claude Code, Codex: a `>` or `❯` line under a rule of
/// box-drawing characters, sometimes inside a box) is prose, and Type treats
/// it like a chat field. A plain shell prompt is commands; Type stays out of
/// it unless the user turns it on.
public struct TerminalLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case agentPrompt, shell }

    public var kind: Kind
    /// What the user has typed on the line, prompt removed.
    public var text: String

    public static func parse(textBeforeCaret screen: String) -> TerminalLine? {
        var lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let current = lines.popLast() else { return nil }
        let above = lines.last ?? ""

        // Drop a box's left border and the space after it.
        var line = Substring(current)
        if line.first == "│" || line.first == "┃" { line = line.dropFirst() }
        let trimmed = line.drop { $0 == " " }

        if isRule(above), let marker = trimmed.first, marker == ">" || marker == "❯" {
            let text = String(trimmed.dropFirst().drop { $0 == " " })
            return text.isEmpty ? nil : TerminalLine(kind: .agentPrompt, text: text)
        }
        // A shell prompt: everything up to the last "$ ", "% ", "❯ " or "> ".
        let markers = ["$ ", "% ", "❯ ", "> "]
        let ends = markers.compactMap { current.range(of: $0, options: .backwards)?.upperBound }
        guard let end = ends.max() else { return nil }
        let text = String(current[end...])
        return text.isEmpty ? nil : TerminalLine(kind: .shell, text: text)
    }

    /// A horizontal rule of box-drawing characters (at least ten).
    static func isRule(_ line: String) -> Bool {
        line.filter { "─━═╭╮╰╯┌┐└┘".contains($0) }.count >= 10
    }
}
