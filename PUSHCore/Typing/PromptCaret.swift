/// Where the caret is in a terminal agent prompt, counted back from the end
/// of the text — from the keys alone.
///
/// Claude Code draws its own block cursor and leaves Terminal's real cursor
/// at the end of the row, so Accessibility cannot say where the user has
/// moved to. A suggestion drawn at the end then landed on top of the text
/// after the caret (user photo, 2026-10-11). Type suggests only while this
/// says the caret is at the end.
public struct PromptCaret: Equatable, Sendable {
    public enum Move: Equatable, Sendable {
        case left, right
        /// ⌥→: a word on — still at the end if it was there, unknown if not.
        case wordRight
        /// ↑ ↓: another line of the prompt — or, in an empty one, a past
        /// message recalled with the caret at its end. The caller decides.
        case vertical
        case toEnd
        /// Home, ⌘←, ⌥←, ⌃A, page keys: somewhere not counted.
        case elsewhere
        /// Forward delete: a character after the caret goes.
        case deleteForward
    }

    /// Characters between the caret and the end; nil when not known.
    public private(set) var fromEnd: Int? = 0

    public init() {}

    public var atEnd: Bool { fromEnd == 0 }

    /// The move a key makes, or nil for keys that do not move the caret.
    public static func move(keyCode: Int64, command: Bool, option: Bool, control: Bool) -> Move? {
        if control, !command {
            switch keyCode {
            case 14: return .toEnd       // ⌃E
            case 0: return .elsewhere    // ⌃A
            case 11: return .left        // ⌃B
            case 3: return .right        // ⌃F
            default: break
            }
        }
        switch keyCode {
        case 123: return command || option ? .elsewhere : .left
        case 124: return command ? .toEnd : option ? .wordRight : .right
        case 125, 126: return command ? .elsewhere : .vertical
        case 119: return .toEnd
        case 115, 116, 121: return .elsewhere
        case 117: return .deleteForward
        default: return nil
        }
    }

    public mutating func apply(_ move: Move) {
        switch move {
        case .left: fromEnd = fromEnd.map { $0 + 1 }
        case .right, .deleteForward: fromEnd = fromEnd.map { max(0, $0 - 1) }
        case .wordRight: if fromEnd != 0 { fromEnd = nil }
        case .toEnd: fromEnd = 0
        case .vertical, .elsewhere: fromEnd = nil
        }
    }

    /// The prompt was sent or emptied: the caret is at its (empty) end.
    public mutating func reset() { fromEnd = 0 }
}
