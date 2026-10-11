/// Which keys accept a suggestion. Both are swallowed only while a suggestion
/// is showing; every other key passes through untouched.
public enum AcceptKeyResolver {
    public struct Key: Sendable, Equatable {
        public var keyCode: Int64
        public var option: Bool
        /// ⌥Tab, used because no key in the layout types a backtick.
        public var isFallback: Bool { self == AcceptKeyResolver.optionTab }

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
    static let optionTab = Key(keyCode: 48, option: true)

    /// Tab, or → in terminals, where Tab is the shell's completion.
    public static func nextWordKey(surface: SurfaceClass) -> Key {
        surface == .terminal ? rightArrow : tab
    }

    /// The key that types `` ` `` unshifted in the current layout — matched by
    /// character, not position, so it is right on non-US keyboards.
    /// `layout` maps key codes to what they type (from UCKeyTranslate).
    public static func wholeSuggestionKey(layout: [Int64: String]) -> Key {
        layout.filter { $0.value == "`" }.keys.min().map { Key(keyCode: $0, option: false) } ?? optionTab
    }
}
