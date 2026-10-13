/// Which keys accept a suggestion. Both are swallowed only while a suggestion
/// is showing; every other key passes through untouched.
public enum AcceptKeyResolver {
    public struct Key: Sendable, Equatable {
        public var keyCode: Int64
        public var option: Bool

        public init(keyCode: Int64, option: Bool) {
            self.keyCode = keyCode
            self.option = option
        }

        /// How it is saved: the key code, and "+opt" with ⌥.
        public var stored: String { option ? "\(keyCode)+opt" : "\(keyCode)" }

        public init?(stored: String) {
            let option = stored.hasSuffix("+opt")
            guard let code = Int64(option ? String(stored.dropLast(4)) : stored) else { return nil }
            self.init(keyCode: code, option: option)
        }

        /// Exact match: ⇧Tab, ⌘Tab and friends are not this key.
        public func matches(keyCode: Int64, option: Bool, otherModifiers: Bool) -> Bool {
            keyCode == self.keyCode && option == self.option && !otherModifiers
        }
    }

    public static let tab = Key(keyCode: 48, option: false)
    static let rightArrow = Key(keyCode: 124, option: false)
    /// ⌥Tab is never an accept key: it sends a plain Tab (Cotypist's way out
    /// of a suggestion when moving between form fields).
    static let optionTab = Key(keyCode: 48, option: true)

    public static func isPlainTabRequest(keyCode: Int64, option: Bool, otherModifiers: Bool) -> Bool {
        optionTab.matches(keyCode: keyCode, option: option, otherModifiers: otherModifiers)
    }

    /// The chosen key (Tab by default), except Tab becomes → in terminals,
    /// where Tab is the shell's completion.
    public static func nextWordKey(surface: SurfaceClass, chosen: Key = tab) -> Key {
        surface == .terminal && chosen == tab ? rightArrow : chosen
    }

    /// Why a key cannot accept suggestions, or nil if it can. An accept key is
    /// swallowed while a suggestion shows, so it must not be one the user
    /// needs for writing. `character`: what the key types unshifted.
    public static func refusal(_ key: Key, character: String?) -> String? {
        if key == optionTab { return "⌥Tab is kept for moving to the next field." }
        switch key.keyCode {
        case 53: return "Esc is how you dismiss a suggestion."
        case 36, 76: return "Return sends messages and starts new lines."
        case 51, 117: return "Delete is for fixing text."
        case 49: return "Space is for typing."
        default: break
        }
        if !key.option, let c = character?.first, c.isLetter || c.isNumber {
            return "That key types \(c.isLetter ? "letters" : "numbers"). Choose another, or hold ⌥ with it."
        }
        return nil
    }

    /// The key as the user sees it: "Tab", "→", "F5", or the character on
    /// the key ("` ~" for the backtick key, as its keycap shows), "⌥" first.
    public static func name(of key: Key, layout: [Int64: String]) -> String {
        let named: [Int64: String] = [
            48: "Tab", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End",
            116: "Page Up", 121: "Page Down", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        let base: String
        if let name = named[key.keyCode] {
            base = name
        } else if let typed = layout[key.keyCode], !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = typed == "`" ? "` ~" : typed.uppercased()
        } else {
            base = "Key \(key.keyCode)"
        }
        return (key.option ? "⌥" : "") + base
    }

    /// The key that types `` ` `` unshifted in the current layout — matched by
    /// character, not position, so it is right on non-US keyboards.
    /// `layout` maps key codes to what they type (from UCKeyTranslate).
    /// With no backtick in the layout, the key above Tab, whatever it types
    /// (§ or ^ on ISO keyboards — key code 10; 50 on ANSI ones), like Cotypist.
    public static func wholeSuggestionKey(layout: [Int64: String]) -> Key {
        if let code = layout.filter({ $0.value == "`" }).keys.min() { return Key(keyCode: code, option: false) }
        let iso = !(layout[10] ?? "").isEmpty
        return Key(keyCode: iso ? 10 : 50, option: false)
    }
}
