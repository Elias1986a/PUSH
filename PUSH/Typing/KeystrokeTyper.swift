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
                // So Type's own tap knows this text came from PUSH, not the user.
                event.setIntegerValueField(.eventSourceUserData, value: TypingKeyTap.ownEventMarker)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Presses Delete `count` times: the first half of swapping in a spelling
    /// fix. Carries the same marker, and the character a real Delete key
    /// reports, so Type's tap takes each one off its own copy of the text.
    static func backspace(_ count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .privateState)
        let delete = Array("\u{7f}".utf16)
        for _ in 0..<count {
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: keyDown) else { continue }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: TypingKeyTap.ownEventMarker)
                event.keyboardSetUnicodeString(stringLength: delete.count, unicodeString: delete)
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
