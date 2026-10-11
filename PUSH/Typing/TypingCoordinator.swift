import AppKit
import PUSHCore

/// Where a suggestion is drawn. Pure, so it is pinned by tests.
enum TypingPlacement {
    static let tallField: CGFloat = 200
    static func decide(caretRect: CGRect?, after: String?, fieldFrame: CGRect?) -> GhostTextPanel.Placement? {
        let restOfLine = (after ?? "").prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        if let caretRect, restOfLine.isEmpty { return .inline(caret: caretRect, field: fieldFrame) }
        if let caretRect { return .card(below: caretRect) }
        // No caret: under the field, unless it is tall (a message body) — then
        // inside its top-left corner, where the card cannot fall off screen.
        if let fieldFrame {
            if fieldFrame.height <= tallField { return .card(below: fieldFrame) }
            return .card(below: CGRect(x: fieldFrame.minX + 8, y: fieldFrame.maxY - 40, width: 0, height: 0))
        }
        return nil
    }
}

/// Apps Type never suggests in. Password fields are refused everywhere on top
/// of this (`FocusSnapshot.isSecure`).
enum TypingExclusions {
    private static let prefixes = [
        "com.1password.", "com.agilebits.", "com.bitwarden.", "com.lastpass.", "com.dashlane.",
        "com.apple.keychainaccess", "com.apple.passwords", "com.apple.systempreferences",
        "com.push.voicetotext",
    ]

    /// The built-in list, then the apps the user turned Type off in.
    static func isExcluded(bundleID: String?, userExcluded: [String] = []) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return prefixes.contains { id.hasPrefix($0) } || userExcluded.contains { $0.lowercased() == id }
    }
}

/// Runs Type: keystrokes in, a suggestion out. Debounces, reads the field off
/// the main thread, builds the prompt, streams from the engine, draws the
/// suggestion, and types it on accept. Never logs text.
@MainActor
final class TypingCoordinator {
    static let shared = TypingCoordinator()

    /// Short: generation is cancelled within a token when a newer key lands,
    /// so the pause only collapses bursts. Cotabby uses 20 ms; Cotypist
    /// "updates to the word you wanted within a letter or two".
    static let debounce: Duration = .milliseconds(50)

    private struct Shown {
        var text: String
        var placement: GhostTextPanel.Placement
        /// The field's character after the caret, for "space after the last word".
        var nextInField: Character?
        /// What it was made from; nil for a Dictionary completion.
        var request: Request?
        /// The whole suggestion as first shown: accepting all of it leaves the
        /// field at `request.before + full`, whatever was taken word by word.
        var full: String
    }

    /// Everything a suggestion is made from, kept so the next one can be made
    /// before the field is read again.
    private struct Request {
        var before: String
        var after: String?
        var surfaceLine: String?
        var style: String?
        var userName: String?
        var examples: [String]
        var clipboard: String?
        var screen: String?
        var surface: SurfaceClass
        var length: LengthPreset

        var prompt: (text: String, forced: String) {
            let heal = TokenHealing.split(before)
            let context = TypingContext(before: heal.prompt, after: after, surfaceLine: surfaceLine, style: style,
                                        userName: userName, clipboard: clipboard, screen: screen, examples: examples)
            return (TypingPrompt.render(context), heal.forced)
        }

        func continued(by text: String) -> Request {
            var next = self
            next.before += text
            return next
        }
    }

    /// The suggestion that will follow the one on screen if all of it is
    /// accepted — made in the background, so it shows the moment it is needed.
    private var prefetchTask: Task<Void, Never>?
    private var prefetched: (before: String, text: String)?

    private var active = false
    /// While the onboarding try-it box is on screen, PUSH's own windows get
    /// suggestions too (they are excluded everywhere else).
    var allowsOwnWindows = false
    private var indicatorTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    /// The character after the caret when the last suggestion was asked for.
    private var nextInField: Character?
    /// The app the user last typed in, for the menu's "Turn Off in <App>".
    private(set) var lastApp: (bundleID: String, name: String)?
    private var buffer = KeystrokeBuffer()
    private var keystrokes = 0          // bumps on every user key; stale work compares against it
    private var debounceTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var shown: Shown?
    /// The field the keystroke buffer belongs to.
    private var bufferElement: Int?
    /// The field the last suggestion was made for, and an Esc pause on it:
    /// Esc means "not now", so the next keystroke must not bring one straight
    /// back (Cotypist pauses the field for a few seconds too).
    private var suggestedElement: Int?
    private var paused: (element: Int, until: Date)?
    static let escPause: TimeInterval = 3

    /// On while Type is switched on. Starts and stops the key tap.
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            let tap = TypingKeyTap.shared
            tap.setKeys(nextWord: AcceptKeyResolver.nextWordKey(surface: .other),
                        whole: AcceptKeyResolver.wholeSuggestionKey(layout: KeyboardLayoutMap.current()))
            tap.onEvent = { [weak self] event in self?.handle(event) }
            tap.start()
            ClipboardContext.shared.start()
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshIndicator(after: .milliseconds(300)) }
            }
            refreshIndicator(after: .milliseconds(300))
        } else {
            TypingKeyTap.shared.stop()
            ClipboardContext.shared.stop()
            if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
            activationObserver = nil
            cancelWork()
            hideAll()
        }
    }

    /// Type stands down here (dictation, a pause, Type switched off): the
    /// suggestion and the field icon both go.
    func hideAll() {
        indicatorTask?.cancel()
        TypeIndicatorPanel.shared.hide()
        hide()
    }

    /// The field icon again, after a setting changed what it shows.
    func refreshIndicator() { refreshIndicator(after: .zero) }

    /// Takes the suggestion down (a key that does not continue it, Esc).
    func hide() {
        shown = nil
        GhostTextPanel.shared.hide()
        TypingKeyTap.shared.setSuggestionVisible(false)
    }

    // MARK: - Events

    private func handle(_ event: TypingKeyTap.Event) {
        switch event {
        case .click:
            buffer.apply(.reset)
            cancelWork()
            hide()
            refreshIndicator(after: .milliseconds(250))
        case .dismiss:
            cancelWork()
            hide()
            if let element = suggestedElement { paused = (element, Date().addingTimeInterval(Self.escPause)) }
        case .own(let text):
            buffer.apply(.text(text))
        case .acceptWord:
            accept(whole: false)
        case .acceptAll:
            accept(whole: true)
        case .key(let key):
            guard key != .ignore else { return }
            buffer.apply(key)
            keystrokes &+= 1
            generationTask?.cancel()
            prefetchTask?.cancel()   // a ready suggestion stays usable if the keys match it
            // Typing into the suggestion keeps the rest of it on screen.
            if case .text(let typed) = key, let current = shown,
               let rest = SuggestionText.remainder(of: current.text, afterTyping: typed) {
                shown?.text = rest
                advanceCaret(by: typed)
                refreshPlacement(after: .milliseconds(300))
            } else {
                hide()
            }
            scheduleSuggestion()
        }
    }

    private func accept(whole: Bool) {
        guard let current = shown else { return }
        // What is on screen is what gets typed: a generation still streaming
        // would put the words just accepted back on screen ("to to").
        generationTask?.cancel()
        let chunk = whole ? current.text : SuggestionText.nextChunk(of: current.text)
        if let rest = SuggestionText.remainder(of: current.text, afterTyping: chunk) {
            KeystrokeTyper.type(chunk)
            shown?.text = rest
            advanceCaret(by: chunk)
            refreshPlacement(after: .milliseconds(300))
            return
        }
        let after = fieldAfterAccepting(current)
        let typed = chunk + (after?.typedSpace == true ? " " : "")
        KeystrokeTyper.type(typed)
        // The next suggestion, at once: ready-made when the prefetch matches,
        // otherwise made now from what the field will hold — no waiting for
        // the app to report the text just typed.
        guard let request = current.request, let after, case .inline(let caret, let field) = current.placement,
              SuggestionText.shouldSuggest(before: after.before, after: request.after) else {
            hide()
            scheduleSuggestion()
            return
        }
        hide()
        let moved = caret.offsetBy(dx: GhostTextPanel.width(of: typed, caretHeight: caret.height), dy: 0)
        let placement = GhostTextPanel.Placement.inline(caret: moved, field: field)
        let next = request.continued(by: String(after.before.dropFirst(request.before.count)))
        if let ready = prefetched, ready.before == next.before {
            prefetched = nil
            show(ready.text, at: placement, surface: next.surface, request: next)
            if let shown { startPrefetch(after: shown) }
        } else {
            startGeneration(next, placement: placement, stamp: keystrokes, wordBoundary: false)
        }
    }

    // MARK: - Suggesting

    private func cancelWork() {
        debounceTask?.cancel()
        generationTask?.cancel()
        prefetchTask?.cancel()
    }

    private func scheduleSuggestion() {
        debounceTask?.cancel()
        let stamp = keystrokes
        debounceTask = Task {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, stamp == keystrokes else { return }
            await suggest(stamp: stamp)
        }
    }

    private var mayRun: Bool {
        let state = AppState.shared
        return active && state.typeEnabled && state.typingModelReady
            && !state.isListening && !state.isProcessing && !Teleprompter.isRunning
            && (state.typingPausedUntil.map { $0 <= Date() } ?? true)
            && !(state.typingPauseOnBattery && PowerSource.shouldConserve)
    }

    /// Why no suggestion was made — rule names only, never text (Cotabby
    /// logs its suppression reasons too; without them a quiet rule is
    /// indistinguishable from a broken one).
    private func skip(_ reason: String) {
        PushLogger.log("TypingCoordinator: no suggestion — \(reason)")
    }

    /// The surface Type works on in this field, or nil — with the rule
    /// logged when `log` is set. The suggestion and the field icon both ask.
    private func supportedSurface(_ focus: FocusSnapshot, log: Bool) -> SurfaceClass? {
        func no(_ reason: String) -> SurfaceClass? {
            if log { skip(reason) }
            return nil
        }
        guard !focus.isSecure else { return no("secure field") }
        guard focus.isTextInput else { return no("not a text field (\(focus.role ?? "?"))") }
        if focus.pid == ProcessInfo.processInfo.processIdentifier {
            // PUSH's own windows only for the onboarding try-it box.
            guard allowsOwnWindows else { return no("excluded app") }
        } else if TypingExclusions.isExcluded(bundleID: focus.bundleID, userExcluded: AppState.shared.typingExcludedApps) {
            return no("excluded app")
        }
        // Sign-in and verification fields, and Mail's header rows (Tab moves
        // to the next field there).
        guard !FieldPolicy.isMailHeader(bundleID: focus.bundleID, role: focus.role) else { return no("mail header") }
        guard !FieldPolicy.isCredentialField(role: focus.role, labels: focus.labels,
                                             domIdentifier: focus.domIdentifier, text: focus.before) else {
            return no("sign-in field")
        }
        let surface = SurfaceClass.classify(bundleID: focus.bundleID)
        guard surface != .code || AppState.shared.typingInCodeEditors else { return no("code editor") }
        return surface
    }

    // MARK: - Field icon

    /// The focused field: PUSH's own try-it box directly, anything else
    /// through Accessibility off the main thread.
    private func readFocus() async -> FocusSnapshot? {
        if allowsOwnWindows, let own = FocusReader.readOwn() { return own }
        return await Task.detached(priority: .userInitiated) { FocusReader.read() }.value
    }

    /// The field icon for `focus`: shown where Type works, hidden elsewhere.
    private func updateIndicator(for focus: FocusSnapshot?) {
        guard mayRun, AppState.shared.typingShowIndicator, let focus, let field = focus.fieldFrame,
              let surface = supportedSurface(focus, log: false),
              surface != .terminal || TerminalLine.parse(textBeforeCaret: focus.before ?? "")?.kind == .agentPrompt
        else {
            TypeIndicatorPanel.shared.hide()
            return
        }
        TypeIndicatorPanel.shared.show(field: field, caret: focus.caretRect, color: AppState.shared.typingColor.color)
    }

    /// Focus may have moved without a key (a click, another app in front):
    /// read it again and place or hide the icon.
    private func refreshIndicator(after delay: Duration) {
        indicatorTask?.cancel()
        indicatorTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            guard mayRun, AppState.shared.typingShowIndicator else { return TypeIndicatorPanel.shared.hide() }
            let focus = await readFocus()
            guard !Task.isCancelled else { return }
            updateIndicator(for: focus)
        }
    }

    private func suggest(stamp: Int) async {
        guard mayRun else { return }
        guard let focus = await readFresh(stamp: stamp) else { return skip("no focused element") }
        guard stamp == keystrokes, mayRun else { return }
        if let id = focus.bundleID, focus.pid != ProcessInfo.processInfo.processIdentifier, focus.isTextInput {
            lastApp = (id, focus.appName ?? id)
        }
        guard let surface = supportedSurface(focus, log: true) else {
            TypeIndicatorPanel.shared.hide()
            return
        }
        updateIndicator(for: focus)
        if let paused, paused.element == focus.elementID, Date() < paused.until { return skip("esc pause") }
        suggestedElement = focus.elementID

        // Keys typed into another field are not this field's text.
        if focus.elementID != bufferElement {
            if bufferElement != nil { buffer.apply(.reset) }
            bufferElement = focus.elementID
        }
        var before = focus.before ?? buffer.text
        var surfaceLine = SurfaceLine.render(surface: surface, appName: focus.appName, windowTitle: focus.windowTitle,
                                             url: focus.url, placeholder: focus.placeholder)
        if surface == .terminal {
            // Only an agent's prompt (prose); a plain shell is commands.
            guard let line = TerminalLine.parse(textBeforeCaret: before), line.kind == .agentPrompt else {
                TypeIndicatorPanel.shared.hide()
                return skip("terminal, not an agent prompt")
            }
            before = line.text
            surfaceLine = SurfaceLine.render(surface: .chat, appName: focus.appName, windowTitle: focus.windowTitle,
                                             url: nil, placeholder: nil)
        }
        if surface != .terminal {
            TypingHistoryStore.shared.observe(element: focus.elementID, bundleID: focus.bundleID, before: before)
        }
        guard SuggestionText.shouldSuggest(before: before, after: surface == .terminal ? nil : focus.after) else {
            return skip("too little text, or caret inside a word")
        }
        guard let placement = TypingPlacement.decide(
            caretRect: focus.caretRect, after: focus.after, fieldFrame: focus.fieldFrame) else {
            return skip("no caret or field position")
        }

        // A name or term from the user's Dictionary, finished without the model.
        if let partial = SuggestionText.caretWords(before).partial,
           let rest = DictionaryCompletion.complete(partial: partial, vocabulary: Self.vocabulary,
                                                    isRealWord: { NSSpellChecker.shared.checkSpelling(of: $0, startingAt: 0).location == NSNotFound }) {
            generationTask?.cancel()
            nextInField = surface == .terminal ? nil : focus.after?.first
            show(rest, at: placement, surface: surface, request: nil)
            return
        }
        // A typo at the caret: whatever follows would build on it (Cotabby
        // holds completions while one forms; Cotypist says fix it first).
        guard !Self.typoAtCaret(before) else { return skip("typo at caret") }
        let request = Request(
            before: before, after: surface == .terminal ? nil : focus.after,
            surfaceLine: surfaceLine,
            style: Self.nonEmpty(AppState.shared.typingAbout),
            userName: TypingPreferences.signOffName(saved: AppState.shared.typingName),
            examples: surface == .terminal ? [] : TypingHistoryStore.shared.examples(
                before: before, bundleID: focus.bundleID, windowTitle: focus.windowTitle),
            clipboard: surface != .terminal && AppState.shared.typingUsesClipboard
                ? ClipboardContext.shared.text(for: before) : nil,
            screen: nil,
            surface: surface, length: AppState.shared.typingLength)
        nextInField = surface == .terminal ? nil : focus.after?.first
        if let ready = prefetched, ready.before == before {
            show(ready.text, at: placement, surface: surface, request: request)
            return
        }
        startGeneration(request, placement: placement, stamp: stamp, wordBoundary: false)
    }

    /// Streams one suggestion. When the model glues letters onto the word at
    /// the caret, the joined word must be a real one ("appreci" + "ate");
    /// otherwise ("Hello" + "u") it asks again with a word break forced after
    /// the word — Cotabby checks the caret word with the spell checker too.
    private func startGeneration(_ request: Request, placement: GhostTextPanel.Placement, stamp: Int,
                                 wordBoundary: Bool) {
        generationTask?.cancel()
        prefetchTask?.cancel()
        let (prompt, forced) = request.prompt
        generationTask = Task {
            var raw = ""
            var judge = SuggestionJudge(forced: forced, before: request.before, length: request.length,
                                        wordBoundary: wordBoundary, isRealWord: Self.isRealWord)
            let grammar = TokenHealing.grammar(forcing: forced, wordBoundary: wordBoundary)
            /// False when this attempt is over (rejected, or retried).
            @MainActor func consider(final: Bool) -> Bool {
                switch judge.judge(raw, final: final) {
                case .wait:
                    return true
                case .show(let text):
                    show(text, at: placement, surface: request.surface, request: request)
                    return true
                case .retryWithBoundary:
                    startGeneration(request, placement: placement, stamp: stamp, wordBoundary: true)
                    return false
                case .reject(let reason):
                    // A later piece turned it unacceptable: take down what an
                    // earlier piece showed (", " before "I'm a 17…") and stop.
                    skip(reason)
                    if reason != "empty after cleanup" { hide() }
                    return false
                }
            }
            do {
                for try await piece in await LlamaEngine.shared.complete(
                    prompt: prompt, maxTokens: request.length.maxTokens, grammar: grammar) {
                    guard stamp == keystrokes, !Task.isCancelled else { return }
                    raw += piece
                    if !consider(final: false) { return }
                }
                guard stamp == keystrokes, !Task.isCancelled else { return }
                if consider(final: true), let current = shown, current.request?.before == request.before {
                    startPrefetch(after: current)
                }
            } catch {
                PushLogger.log("TypingCoordinator: generation failed: \(error)")
            }
        }
    }

    /// The field once all of `shown` is accepted (with the space after it,
    /// when that setting applies).
    private func fieldAfterAccepting(_ shown: Shown) -> (typedSpace: Bool, before: String)? {
        guard let request = shown.request else { return nil }
        let spaced = AppState.shared.typingSpaceAfterLastWord
            && SuggestionText.needsTrailingSpace(finishing: shown.full, nextInField: shown.nextInField)
        return (spaced, request.before + shown.full + (spaced ? " " : ""))
    }

    /// Makes the suggestion that follows `shown` in the background. Cancelled
    /// by any key, click or new request; the engine stops within a token.
    private func startPrefetch(after shown: Shown) {
        prefetchTask?.cancel()
        prefetched = nil
        guard let request = shown.request, let after = fieldAfterAccepting(shown) else { return }
        let next = request.continued(by: String(after.before.dropFirst(request.before.count)))
        guard SuggestionText.shouldSuggest(before: next.before, after: next.after) else { return }
        let (prompt, forced) = next.prompt
        prefetchTask = Task {
            var judge = SuggestionJudge(forced: forced, before: next.before, length: next.length,
                                        wordBoundary: false, isRealWord: Self.isRealWord)
            var raw = ""
            do {
                for try await piece in await LlamaEngine.shared.complete(
                    prompt: prompt, maxTokens: next.length.maxTokens,
                    grammar: TokenHealing.grammar(forcing: forced)) {
                    guard !Task.isCancelled else { return }
                    raw += piece
                }
            } catch { return }
            guard !Task.isCancelled, case .show(let text) = judge.judge(raw, final: true) else { return }
            prefetched = (next.before, text)
        }
    }

    /// Reads the field, again (up to three times, 60 ms apart) while its text
    /// does not yet end with the last keys typed: Notes updates what
    /// Accessibility reports a beat after drawing, and a stale read ("…would
    /// love" with "to" already typed) made the model suggest " to see you".
    private func readFresh(stamp: Int) async -> FocusSnapshot? {
        let typed = String(buffer.text.suffix(3))
        var focus: FocusSnapshot?
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(60)) }
            guard stamp == keystrokes else { return nil }
            focus = await readFocus()
            guard let snapshot = focus, let before = snapshot.before, !typed.isEmpty,
                  snapshot.elementID == bufferElement else { return focus }
            if before.hasSuffix(typed) { return focus }
        }
        return focus   // still differs (autocorrect rewrote it, say): go with the field
    }

    /// The last finished word is misspelled, or the word being typed is
    /// neither a word nor the start of one ("apprec" is in progress, fine).
    private static func typoAtCaret(_ before: String) -> Bool {
        // Capitalised words are usually names ("Priya"), which the checker
        // does not know: never a reason to stand down.
        func checkable(_ word: String) -> Bool { word.count > 1 && word.first?.isLowercase == true }
        let words = SuggestionText.caretWords(before)
        if let finished = words.finished, checkable(finished), !isRealWord(finished) { return true }
        if let partial = words.partial, partial.count >= 3, checkable(partial), !isRealWord(partial) {
            let range = NSRange(location: 0, length: (partial as NSString).length)
            let completions = NSSpellChecker.shared.completions(forPartialWordRange: range, in: partial,
                                                                language: nil, inSpellDocumentWithTag: 0)
            if completions?.isEmpty ?? true { return true }
        }
        return false
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A dictionary word, or one in the user's PUSH Dictionary ("Hamer" is
    /// never a typo to hold back for).
    private static func isRealWord(_ word: String) -> Bool {
        vocabulary.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
            || NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }

    /// The words of the PUSH Dictionary's right-hand side. A few dozen
    /// entries: rebuilt when asked rather than cached and invalidated.
    private static var vocabulary: Set<String> {
        DictionaryCompletion.vocabulary(from: CorrectionsStore.shared.corrections.map(\.right))
    }

    private func show(_ text: String, at placement: GhostTextPanel.Placement, surface: SurfaceClass,
                      request: Request?) {
        guard mayRun, !text.isEmpty else { return }
        let appearing = shown == nil
        // → in terminals, where Tab is the shell's completion.
        if appearing {
            TypingKeyTap.shared.setKeys(nextWord: AcceptKeyResolver.nextWordKey(surface: surface),
                                        whole: AcceptKeyResolver.wholeSuggestionKey(layout: KeyboardLayoutMap.current()))
        }
        // What fits on screen is the suggestion: accepting never types words
        // the user could not see.
        GhostTextPanel.shared.textColor = AppState.shared.typingColor.color
        guard let visible = GhostTextPanel.shared.show(text, at: placement) else {
            if appearing { hide() }
            return
        }
        shown = Shown(text: visible, placement: placement, nextInField: nextInField, request: request, full: visible)
        TypingKeyTap.shared.setSuggestionVisible(true)
        // An app can still be drawing the last keys (or rewriting them, like
        // TextEdit's text replacement) when the caret was read: measure again.
        if appearing { refreshPlacement(after: .milliseconds(200)) }
    }

    /// Where the caret must be after `typed` went in, drawn at once — the app
    /// may not have drawn the text yet, and re-reading now would put the rest
    /// of the suggestion on top of it.
    private func advanceCaret(by typed: String) {
        guard let current = shown, case .inline(let caret, let field) = current.placement else {
            GhostTextPanel.shared.hide()
            return
        }
        let moved = caret.offsetBy(dx: GhostTextPanel.width(of: typed, caretHeight: caret.height), dy: 0)
        let placement = GhostTextPanel.Placement.inline(caret: moved, field: field)
        shown?.placement = placement
        if let visible = GhostTextPanel.shared.show(current.text, at: placement) { shown?.text = visible }
    }

    /// The caret moved (typed into or accepted part of the suggestion): read
    /// it again and redraw what is left.
    private func refreshPlacement(after delay: Duration = .zero) {
        let stamp = keystrokes
        Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            let focus = await readFocus()
            guard stamp == keystrokes, let current = shown else { return }
            var placement = focus.flatMap {
                TypingPlacement.decide(caretRect: $0.caretRect, after: $0.after, fieldFrame: $0.fieldFrame)
            } ?? current.placement
            // An app still drawing reports the caret where it was: on the same
            // line, never move back left of where the typed text must reach.
            if case .inline(let read, let field) = placement, case .inline(let known, _) = current.placement,
               abs(read.midY - known.midY) < known.height / 2, read.maxX < known.maxX - 1 {
                placement = .inline(caret: known, field: field)
            }
            shown?.placement = placement
            if let visible = GhostTextPanel.shared.show(current.text, at: placement) { shown?.text = visible }
        }
    }
}
