/// What the user typed since focus, a click or a caret move — the "text before
/// the caret" for apps whose fields Accessibility cannot read. Held in memory
/// only: never stored, never logged.
public struct KeystrokeBuffer: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        case text(String), backspace, reset, ignore

        /// macOS virtual key codes that move the caret or edit away from it.
        private static let caretMoves: Set<Int64> = [
            123, 124, 125, 126,  // arrows
            115, 119, 116, 121,  // home, end, page up, page down
            117,                 // forward delete
            53,                  // escape
        ]

        public static func classify(keyCode: Int64, command: Bool, control: Bool, characters: String?) -> Key {
            if command || control { return .reset }      // shortcuts: paste, undo, select all…
            if keyCode == 51 { return .backspace }
            if caretMoves.contains(keyCode) { return .reset }
            if keyCode == 36 || keyCode == 76 { return .text("\n") }   // return, enter
            guard let characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !(0xF700...0xF8FF).contains($0.value) && $0.value >= 0x20 })
            else { return .ignore }                      // bare modifiers, function keys
            return .text(characters)
        }
    }

    public private(set) var text = ""
    private let limit: Int

    public init(limit: Int = 1_500) { self.limit = limit }

    public mutating func apply(_ key: Key) {
        switch key {
        case .text(let typed):
            text += typed
            if text.count > limit { text = String(text.suffix(limit)) }
        case .backspace:
            if !text.isEmpty { text.removeLast() }
        case .reset:
            text = ""
        case .ignore:
            break
        }
    }
}
