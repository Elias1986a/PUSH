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

        /// Exact match: ⇧Tab, ⌘Tab and friends are not this key.
        public func matches(keyCode: Int64, option: Bool, otherModifiers: Bool) -> Bool {
            keyCode == self.keyCode && option == self.option && !otherModifiers
        }
    }

    static let tab = Key(keyCode: 48, option: false)
    static let rightArrow = Key(keyCode: 124, option: false)
    /// ⌥Tab is never an accept key: it sends a plain Tab (Cotypist's way out
    /// of a suggestion when moving between form fields).
    static let optionTab = Key(keyCode: 48, option: true)

    public static func isPlainTabRequest(keyCode: Int64, option: Bool, otherModifiers: Bool) -> Bool {
        optionTab.matches(keyCode: keyCode, option: option, otherModifiers: otherModifiers)
    }

    /// Tab, or → in terminals, where Tab is the shell's completion.
    public static func nextWordKey(surface: SurfaceClass) -> Key {
        surface == .terminal ? rightArrow : tab
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
