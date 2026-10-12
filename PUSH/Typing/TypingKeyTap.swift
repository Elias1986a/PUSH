import AppKit
import PUSHCore

/// Type's own event tap, separate from dictation's `HotkeyManager`. It runs on
/// a dedicated thread with its own run loop, so a stalled main thread cannot
/// get it disabled, and its callback does nothing but classify and hand off.
///
/// Keys are swallowed only while a suggestion is showing, and only the accept
/// keys and Esc. Everything else passes through untouched.
final class TypingKeyTap: @unchecked Sendable {
    static let shared = TypingKeyTap()

    enum Event: Sendable {
        case key(KeystrokeBuffer.Key)
        /// A key that moves the caret (arrows, Home/End, ⌃A/⌃E…), sent just
        /// before its `.key`: terminal agent prompts track the caret from it.
        case caret(PromptCaret.Move)
        /// Text PUSH typed itself (an accepted suggestion).
        case own(String)
        case acceptWord, acceptAll, dismiss, click
    }

    /// Marks events `KeystrokeTyper` posts, so the tap can tell them apart.
    static let ownEventMarker: Int64 = 0x5055_5348   // "PUSH"

    /// Main actor receives every event.
    var onEvent: (@MainActor @Sendable (Event) -> Void)?

    private struct State {
        var suggestionVisible = false
        var nextWord = AcceptKeyResolver.nextWordKey(surface: .other)
        var whole = AcceptKeyResolver.wholeSuggestionKey(layout: [50: "`"])
    }
    private var state = State()
    private let lock = NSLock()
    private var thread: Thread?
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    func setSuggestionVisible(_ visible: Bool) { lock.withLock { state.suggestionVisible = visible } }
    func setKeys(nextWord: AcceptKeyResolver.Key, whole: AcceptKeyResolver.Key) {
        lock.withLock { state.nextWord = nextWord; state.whole = whole }
    }

    func start() {
        guard thread == nil else { return }
        let thread = Thread { [weak self] in self?.runTap() }
        thread.name = "PUSH.TypingKeyTap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard let thread else { return }
        self.thread = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        thread.cancel()
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private func runTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<TypingKeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            PushLogger.log("TypingKeyTap: could not create the event tap (Accessibility?)")
            thread = nil
            return
        }
        self.tap = tap
        self.runLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        PushLogger.log("TypingKeyTap: listening")
        CFRunLoopRun()
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.tap = nil
        PushLogger.log("TypingKeyTap: stopped")
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseDown, .rightMouseDown:
            emit(.click)
            return pass
        case .keyDown:
            break
        default:
            return pass
        }

        let characters = Self.characters(of: event)
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventMarker {
            if let characters { emit(.own(characters)) }
            return pass
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let others = !flags.intersection([.maskCommand, .maskControl, .maskShift]).isEmpty
        let s = lock.withLock { state }
        if s.suggestionVisible {
            if s.nextWord.matches(keyCode: keyCode, option: option, otherModifiers: others) {
                emit(.acceptWord)
                return nil
            }
            if s.whole.matches(keyCode: keyCode, option: option, otherModifiers: others) {
                emit(.acceptAll)
                return nil
            }
            if keyCode == 53, !option, !others {
                emit(.dismiss)
                return nil
            }
            // ⌥Tab: a plain Tab goes to the app. Focus moves to the next form
            // field, so it is handled like a click there.
            if AcceptKeyResolver.isPlainTabRequest(keyCode: keyCode, option: option, otherModifiers: others) {
                event.flags.remove(.maskAlternate)
                emit(.click)
                return pass
            }
        }
        // ⌘⇧3/4/5 take a screenshot; they change no text, so the suggestion stays.
        if flags.contains(.maskCommand), flags.contains(.maskShift), [20, 21, 23].contains(keyCode) {
            return pass
        }
        if let move = PromptCaret.move(keyCode: keyCode, command: flags.contains(.maskCommand), option: option,
                                       control: flags.contains(.maskControl)) {
            emit(.caret(move))
        }
        emit(.key(KeystrokeBuffer.Key.classify(
            keyCode: keyCode, command: flags.contains(.maskCommand), control: flags.contains(.maskControl),
            characters: characters)))
        return pass
    }

    private func emit(_ event: Event) {
        guard let onEvent else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { onEvent(event) } }
    }

    private static func characters(of event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return length > 0 ? String(utf16CodeUnits: buffer, count: length) : nil
    }
}
