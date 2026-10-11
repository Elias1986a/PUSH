import CoreGraphics

/// Types text into the focused field as synthesized Unicode key events, so
/// accepting a few suggested words never touches the clipboard. Dictation
/// keeps pasting (`TextInjector`); this is only for suggestion-sized text.
enum KeystrokeTyper {
    /// Apps read at most 20 UTF-16 units from one event's Unicode string.
    private static let maxUnitsPerEvent = 20

    static func type(_ text: String) {
        // A private source with no flags, so a modifier the user is still
        // holding cannot turn the typed characters into shortcuts.
        let source = CGEventSource(stateID: .privateState)
        for chunk in chunks(of: text) {
            let units = Array(chunk.utf16)
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Splits on character boundaries, so an emoji's surrogate pair or a
    /// combining accent never straddles two events.
    static func chunks(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if current.utf16.count + character.utf16.count > maxUnitsPerEvent, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
