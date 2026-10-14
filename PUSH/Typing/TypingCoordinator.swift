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
    /// "updates to the word you wanted within a letter or two". At 50 ms a
    /// suggestion landed after the next key at ten keys a second.
    static let debounce: Duration = .milliseconds(10)

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
                                        userName: userName, clipboard: clipboard, screen: screen, examples: examples,
                                        date: Date())
            return (TypingPrompt.render(context), heal.forced)
        }

        /// What the user can see besides `before`: numbers in it are theirs.
        var known: String { [after, screen, clipboard].compactMap { $0 }.joined(separator: "\n") }

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
    /// Focus moving inside the frontmost app (Tab to another field, a window
    /// closing): the icon follows it, and a suggestion for the old field goes.
    private lazy var focusObserver = FocusObserver { [weak self] in self?.refreshIndicator(after: .milliseconds(50)) }
    /// The character after the caret when the last suggestion was asked for.
    private var nextInField: Character?
    /// The app the user last typed in, for the menu's "Turn Off in <App>".
    private(set) var lastApp: (bundleID: String, name: String)?
    private var buffer = KeystrokeBuffer()
    private var keystrokes = 0          // bumps on every user key; stale work compares against it
    private var debounceTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var shown: Shown?
    /// The field the last suggestion was made for, and an Esc pause on it:
    /// Esc means "not now", so the next keystroke must not bring one straight
    /// back (Cotypist pauses the field for a few seconds too).
    private var suggestedElement: Int?
    private var paused: (element: Int, until: Date)?
    static let escPause: TimeInterval = 3

    /// The accept keys for this surface: the user's choices, read as each
    /// suggestion appears so a change in Settings applies at once.
    private static func applyKeys(surface: SurfaceClass) {
        TypingKeyTap.shared.setKeys(
            nextWord: AcceptKeyResolver.nextWordKey(surface: surface, chosen: TypingPreferences.nextWordKey()),
            whole: TypingPreferences.wholeKey(layout: KeyboardLayoutMap.current()))
    }

    /// On while Type is switched on. Starts and stops the key tap.
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            let tap = TypingKeyTap.shared
            Self.applyKeys(surface: .other)
            tap.onEvent = { [weak self] event in self?.handle(event) }
            tap.start()
            ClipboardContext.shared.start()
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // The suggestion belonged to the app left behind.
                    self.hide()
                    self.focusObserver.observe(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                    self.refreshIndicator(after: .milliseconds(300))
                }
            }
            focusObserver.observe(NSWorkspace.shared.frontmostApplication)
            refreshIndicator(after: .milliseconds(300))
        } else {
            TypingKeyTap.shared.stop()
            ClipboardContext.shared.stop()
            if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
            activationObserver = nil
            focusObserver.stop()
            buffer = KeystrokeBuffer()
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
        watchTask?.cancel()
        shown = nil
        correction = nil
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
            // PUSH's own Delete presses (a spelling fix) take a character off.
            buffer.apply(text == "\u{7f}" ? .backspace : .text(text))
        case .paste:
            scheduleSuggestion(after: Self.pasteSettle)
        case .caret(let move):
            guard lastSurface == .terminal else { return }
            // ↑ in an empty prompt recalls a past message, caret at its end.
            promptCaret.apply(move == .vertical && promptText.isEmpty ? .toEnd : move)
        case .acceptWord:
            if let fix = correction { return applyCorrection(fix) }
            accept(whole: false)
        case .acceptAll:
            if let fix = correction { return applyCorrection(fix) }
            accept(whole: true)
        case .key(let key):
            guard key != .ignore else { return }
            buffer.apply(key)
            keystrokes &+= 1
            // Return at an agent prompt sends the message: nothing to suggest
            // until the user types again (the screen still showed the sent
            // text for a moment, and a suggestion for it stayed behind).
            if key == .text("\n"), lastSurface == .terminal {
                promptCaret.reset()
                cancelWork()
                hide()
                return
            }
            // Typing into the middle of an agent prompt: a suggestion there
            // would be drawn over the text after the caret.
            if lastSurface == .terminal, !promptCaret.atEnd { hide() }
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
        // A terminal agent re-flows its prompt as text arrives (a row fills,
        // the text moves down), so where the caret lands is read, not
        // predicted; a ready-made next suggestion is still used once it is.
        if current.request?.surface == .terminal {
            hide()
            scheduleSuggestion(after: Self.terminalSettle)
            return
        }
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
        let moved = caret.offsetBy(dx: advance(of: typed, caretHeight: caret.height), dy: 0)
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

    /// How long a paste takes to land in the field (Claude Code, Electron
    /// apps): read before that, the field still held the old text and no
    /// suggestion came until the next key — after every dictation.
    static let pasteSettle: Duration = .milliseconds(300)
    /// How long a terminal agent takes to draw text PUSH typed into it.
    static let terminalSettle: Duration = .milliseconds(120)

    private func scheduleSuggestion(after delay: Duration = TypingCoordinator.debounce) {
        debounceTask?.cancel()
        let stamp = keystrokes
        debounceTask = Task {
            try? await Task.sleep(for: delay)
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
        // A browser's own fields — the address bar above all, which completes
        // addresses itself — are not the page: only fields inside it.
        guard surface != .browser || focus.insideWebPage else { return no("browser address bar") }
        return surface
    }

    // MARK: - Screen text

    /// The text around the field, from a cache kept per field: reading a
    /// window can take a while, and a suggestion never waits for it. A field
    /// seen for the first time gets it from its second request on (the read
    /// starts on the click or app switch that focused it, so usually sooner).
    private var screenCache: (element: Int, text: String?, at: Date)?
    private var screenTask: Task<Void, Never>?
    /// Old enough to read again (a chat gets new messages). The text only
    /// changes the prompt when it changed, so the model's cache keeps matching.
    static let screenRefresh: TimeInterval = 6

    private func screenText(for focus: FocusSnapshot) -> String? {
        guard AppState.shared.typingUsesScreen else { return nil }
        guard let cache = screenCache, cache.element == focus.elementID else {
            refreshScreen(for: focus)
            return nil
        }
        if Date().timeIntervalSince(cache.at) > Self.screenRefresh { refreshScreen(for: focus) }
        return cache.text
    }

    private func refreshScreen(for focus: FocusSnapshot) {
        guard AppState.shared.typingUsesScreen, screenTask == nil, let field = focus.fieldFrame,
              focus.pid != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = focus.pid
        let element = focus.elementID
        screenTask = Task {
            let started = Date()
            var items = await Task.detached(priority: .utility) { ScreenTextReader.read(pid: pid) }.value
            var source = "accessibility"
            // Next to nothing through Accessibility: read the pixels, when allowed.
            if items.map(\.text.count).reduce(0, +) < 60, ScreenOCR.isAllowed {
                items = await ScreenOCR.read(pid: pid).filter { !field.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                source = "OCR"
            }
            let text = ScreenTextSelector.select(items, field: field)
            // Sizes only, never the text.
            PushLogger.log("TypingCoordinator: screen text \(text?.count ?? 0) chars from \(items.count) items (\(source), "
                           + "\(Int(Date().timeIntervalSince(started) * 1000)) ms)")
            screenTask = nil
            screenCache = (element, text, Date())
        }
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
        placeIndicator(field: field, caret: caret(for: focus, terminal: surface == .terminal), pid: focus.pid)
        // A field just focused: start reading what is around it now.
        if surface != .terminal, screenCache?.element != focus.elementID { refreshScreen(for: focus) }
    }

    /// The chip's spot, worked out off the main thread (Accessibility hit
    /// tests) and kept while the field and the caret's line stay put.
    private var indicatorSpot: (key: [CGFloat], frame: CGRect?)?
    private var placeTask: Task<Void, Never>?

    private func placeIndicator(field: CGRect, caret: CGRect?, pid: pid_t) {
        let line = caret.map { ($0.midY).rounded() } ?? -1
        let key = [field.minX, field.minY, field.width, field.height, line, CGFloat(pid)].map { $0.rounded() }
        if let spot = indicatorSpot, spot.key == key {
            if let frame = spot.frame { TypeIndicatorPanel.shared.show(at: frame, color: AppState.shared.typingColor) }
            else { TypeIndicatorPanel.shared.hide() }
            return
        }
        let screen = (NSScreen.screens.first { $0.frame.intersects(field) } ?? NSScreen.main)?.visibleFrame ?? field
        placeTask?.cancel()
        placeTask = Task {
            let frame = await Task.detached(priority: .userInitiated) {
                TypeIndicatorPanel.place(field: field, caret: caret, screen: screen, pid: pid)
            }.value
            guard !Task.isCancelled, mayRun, AppState.shared.typingShowIndicator else { return }
            indicatorSpot = (key, frame)
            if let frame { TypeIndicatorPanel.shared.show(at: frame, color: AppState.shared.typingColor) }
            else { TypeIndicatorPanel.shared.hide() }
        }
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
            if let focus, buffer.focus(on: focus.elementID, isSecure: focus.isSecure) { promptCaret.reset() }
            if shown != nil, focus?.elementID != suggestedElement { hide() }
            updateIndicator(for: focus)
        }
    }

    private func suggest(stamp: Int) async {
        guard mayRun else { return }
        guard let focus = await readFresh(stamp: stamp) else { return skip("no focused element") }
        guard stamp == keystrokes, mayRun else { return }
        // Before any rule: keys typed into another field, or a password
        // field, are never this field's text.
        if buffer.focus(on: focus.elementID, isSecure: focus.isSecure) { promptCaret.reset() }
        if let id = focus.bundleID, focus.pid != ProcessInfo.processInfo.processIdentifier, focus.isTextInput {
            lastApp = (id, focus.appName ?? id)
        }
        guard let surface = supportedSurface(focus, log: true) else {
            TypeIndicatorPanel.shared.hide()
            return
        }
        updateIndicator(for: focus)
        lastSurface = surface
        if let paused, paused.element == focus.elementID, Date() < paused.until { return skip("esc pause") }
        suggestedElement = focus.elementID

        var before = focus.before ?? buffer.text
        var surfaceLine = SurfaceLine.render(surface: surface, appName: focus.appName, windowTitle: focus.windowTitle,
                                             url: focus.url, placeholder: focus.placeholder)
        var conversation: String?
        if surface == .terminal {
            // Only an agent's prompt (prose); a plain shell is commands.
            guard let line = TerminalLine.parse(textBeforeCaret: before), line.kind == .agentPrompt else {
                TypeIndicatorPanel.shared.hide()
                return skip("terminal, not an agent prompt")
            }
            promptText = line.text
            if line.text.isEmpty { promptCaret.reset() }
            guard promptCaret.atEnd else {
                hide()
                return skip("caret moved back into the prompt")
            }
            before = line.text
            // The row's trailing space is not in the parsed text when Claude
            // Code has moved the cursor off it; the key just typed says so.
            if buffer.text.last == " ", !before.isEmpty, before.last != " " { before += " " }
            conversation = line.context
            surfaceLine = SurfaceLine.render(surface: .chat, appName: focus.appName, windowTitle: focus.windowTitle,
                                             url: nil, placeholder: nil)
        }
        if surface != .terminal {
            TypingHistoryStore.shared.observe(element: focus.elementID, bundleID: focus.bundleID,
                                              windowTitle: focus.windowTitle, before: before)
        }
        guard SuggestionText.shouldSuggest(before: before, after: surface == .terminal ? nil : focus.after) else {
            return skip("too little text, or caret inside a word")
        }
        guard let placement = placement(for: focus, terminal: surface == .terminal) else {
            return skip("no caret or field position")
        }
        terminalCell = surface == .terminal ? focus.textEndRect?.width : nil
        GhostTextPanel.shared.fieldFont = focus.font ?? terminalCell.map(Self.monospaced)
        GhostTextPanel.shared.wrapsToNextLine = surface != .terminal

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
        if Self.typoAtCaret(before) {
            // Offer the spelling fix in place of a continuation, which would
            // only build on the typo.
            // Terminals too: Type only suggests at an agent's prompt there
            // (Claude Code), which is prose, never in a shell command.
            if AppState.shared.typingFixTypos,
               let fix = TypoFix.find(in: before, isTypo: { !Self.isRealWord($0) },
                                      isInProgress: Self.startsARealWord,
                                      guesses: { Self.spellingCorrections(for: $0, in: before) }) {
                nextInField = surface == .terminal ? nil : focus.after?.first
                return showCorrection(fix, at: placement, surface: surface)
            }
            return skip("typo at caret")
        }
        // The user's own habit for these words, learned from all their
        // writing: their phrasing, at once, without the model.
        if surface != .terminal, let habit = TypingHistoryStore.shared.habitContinuation(before: before) {
            generationTask?.cancel()
            nextInField = focus.after?.first
            learningTally.count(habit: true, examples: 0)
            show(habit, at: placement, surface: surface, request: nil)
            return
        }
        let request = Request(
            before: before, after: surface == .terminal ? nil : focus.after,
            surfaceLine: surfaceLine,
            style: Self.nonEmpty(AppState.shared.typingAbout),
            userName: TypingPreferences.signOffName(saved: AppState.shared.typingName),
            examples: surface == .terminal ? [] : TypingHistoryStore.shared.examples(
                before: before, bundleID: focus.bundleID, windowTitle: focus.windowTitle),
            clipboard: surface != .terminal && AppState.shared.typingUsesClipboard
                ? ClipboardContext.shared.text(for: before) : nil,
            screen: surface != .terminal ? screenText(for: focus)
                : AppState.shared.typingUsesScreen ? conversation : nil,
            surface: surface, length: AppState.shared.typingLength)
        nextInField = surface == .terminal ? nil : focus.after?.first
        if surface != .terminal { learningTally.count(habit: false, examples: request.examples.count) }
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
                                        wordBoundary: wordBoundary, known: request.known, isRealWord: Self.isRealWord)
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
                    prompt: prompt, maxTokens: request.length.maxTokens, forcing: forced, wordBoundary: wordBoundary) {
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
                                        wordBoundary: false, known: next.known, isRealWord: Self.isRealWord)
            var raw = ""
            do {
                for try await piece in await LlamaEngine.shared.complete(
                    prompt: prompt, maxTokens: next.length.maxTokens,
                    forcing: forced) {
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
                  snapshot.elementID == buffer.field else { return focus }
            if before.hasSuffix(typed) { return focus }
            // A terminal agent's row ends in its drawn cursor and padding, not
            // the keys: compare its prompt text, or every key waited 120 ms.
            if SurfaceClass.classify(bundleID: snapshot.bundleID) == .terminal,
               let line = TerminalLine.parse(textBeforeCaret: before),
               line.text.trimmingCharacters(in: .whitespaces).hasSuffix(typed.trimmingCharacters(in: .whitespaces)) {
                return focus
            }
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

    /// How much learning is used, logged every 50 suggestions — counts only.
    private var learningTally = LearningTally()

    /// A spelling fix on screen instead of a suggestion.
    private var correction: TypoFix?

    /// Shows "→ receive" where the suggestion would go. The accept keys swap
    /// it in; any other key takes it down, like a suggestion.
    private func showCorrection(_ fix: TypoFix, at placement: GhostTextPanel.Placement, surface: SurfaceClass) {
        guard mayRun else { return }
        generationTask?.cancel()
        prefetchTask?.cancel()
        if shown == nil, correction == nil { Self.applyKeys(surface: surface) }
        GhostTextPanel.shared.textColor = AppState.shared.typingColor.color
        let label = (fix.trailing.isEmpty ? " → " : "→ ") + fix.replacement
        guard GhostTextPanel.shared.show(label, at: placement) != nil else { return hide() }
        shown = nil
        correction = fix
        TypingKeyTap.shared.setSuggestionVisible(true)
    }

    /// Deletes the typo (and the space after it) and types the fix, then
    /// carries on suggesting from the corrected text.
    private func applyCorrection(_ fix: TypoFix) {
        let next = nextInField
        hide()
        // A fix at the caret ends the word: add the space after it, as for an
        // accepted suggestion, unless the field already has one there.
        let spaced = fix.trailing.isEmpty && AppState.shared.typingSpaceAfterLastWord
            && SuggestionText.needsTrailingSpace(finishing: fix.replacement, nextInField: next)
        KeystrokeTyper.backspace(fix.deleteCount)
        KeystrokeTyper.type(fix.typed + (spaced ? " " : ""))
        PushLogger.log("TypingCoordinator: spelling fix accepted")
        scheduleSuggestion(after: Self.terminalSettle)
    }

    /// Whether `partial` is the start of a dictionary word ("apprec" →
    /// "appreciate"): still being typed, not a typo.
    private static func startsARealWord(_ partial: String) -> Bool {
        let range = NSRange(location: 0, length: (partial as NSString).length)
        let completions = NSSpellChecker.shared.completions(forPartialWordRange: range, in: partial,
                                                            language: nil, inSpellDocumentWithTag: 0) ?? []
        return completions.contains { $0.count > partial.count && $0.lowercased().hasPrefix(partial.lowercased()) }
    }

    /// The fix for `word`, best first: macOS's autocorrect pick (what its own
    /// autocorrect would type), then its list of guesses. Both see the
    /// sentence around the word. The guess list alone is poorly ranked —
    /// "recive" lists "recipe" before "receive", and the user got "revive" —
    /// while the autocorrect pick says "receive".
    private static func spellingCorrections(for word: String, in text: String) -> [String] {
        let checker = NSSpellChecker.shared
        let ns = text as NSString
        var range = ns.range(of: word, options: .backwards)
        var context = text
        if range.location == NSNotFound {
            context = word
            range = NSRange(location: 0, length: (word as NSString).length)
        }
        var result: [String] = []
        if let pick = checker.correction(forWordRange: range, in: context, language: checker.language(),
                                         inSpellDocumentWithTag: 0) {
            result.append(pick)
        }
        result += checker.guesses(forWordRange: range, in: context, language: nil, inSpellDocumentWithTag: 0) ?? []
        return result
    }

    private func show(_ text: String, at placement: GhostTextPanel.Placement, surface: SurfaceClass,
                      request: Request?) {
        guard mayRun, !text.isEmpty else { return }
        let appearing = shown == nil
        // → in terminals, where Tab is the shell's completion.
        if appearing { Self.applyKeys(surface: surface) }
        // What fits on screen is the suggestion: accepting never types words
        // the user could not see.
        GhostTextPanel.shared.textColor = AppState.shared.typingColor.color
        guard let visible = GhostTextPanel.shared.show(text, at: placement) else {
            if appearing { hide() }
            return
        }
        shown = Shown(text: visible, placement: placement, nextInField: nextInField, request: request, full: visible)
        TypingKeyTap.shared.setSuggestionVisible(true)
        if appearing, surface == .terminal { watchTerminal() }
        // An app can still be drawing the last keys (or rewriting them, like
        // TextEdit's text replacement) when the caret was read: measure again.
        if appearing { refreshPlacement(after: .milliseconds(200)) }
    }

    /// Takes the suggestion down once the agent prompt no longer holds
    /// exactly the text it was made for plus what was typed into it since —
    /// sent, cleared, or added to without keys (a file dropped in, a paste,
    /// dictation), which left it floating after the new text. Two misses in a
    /// row, so a read taken mid-redraw does not count.
    private func watchTerminal() {
        watchTask?.cancel()
        watchTask = Task {
            var misses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let current = shown, let request = current.request else { return }
                let focus = await readFocus()
                guard !Task.isCancelled, shown != nil else { return }
                let line = (focus?.before).flatMap { TerminalLine.parse(textBeforeCaret: $0) }
                // Typed into the suggestion so far: what is no longer shown of it.
                let consumed = String(current.full.prefix(max(0, current.full.count - current.text.count)))
                func squeezed(_ text: String) -> String {
                    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                }
                let holds = line?.kind == .agentPrompt
                    && squeezed(line?.text ?? "") == squeezed(request.before + consumed)
                misses = holds ? 0 : misses + 1
                if misses >= 2 { return hide() }
            }
        }
    }

    /// Where the caret must be after `typed` went in, drawn at once — the app
    /// may not have drawn the text yet, and re-reading now would put the rest
    /// of the suggestion on top of it.
    private func advanceCaret(by typed: String) {
        guard let current = shown, case .inline(let caret, let field) = current.placement else {
            GhostTextPanel.shared.hide()
            return
        }
        let moved = caret.offsetBy(dx: advance(of: typed, caretHeight: caret.height), dy: 0)
        let placement = GhostTextPanel.Placement.inline(caret: moved, field: field)
        shown?.placement = placement
        if let visible = GhostTextPanel.shared.show(current.text, at: placement) { shown?.text = visible }
    }

    /// Where the user sees the caret. At an agent prompt (Claude Code) the
    /// terminal's real cursor is no guide: the agent draws its own block
    /// cursor a cell after the text and leaves the real one further on, or
    /// on the next row. The caret is after the end of the typed text, past
    /// the spaces typed after it and the block.
    private func caret(for focus: FocusSnapshot, terminal: Bool) -> CGRect? {
        guard terminal, let end = focus.textEndRect,
              TerminalLine.parse(textBeforeCaret: focus.before ?? "")?.kind == .agentPrompt else { return focus.caretRect }
        let cells = CGFloat(buffer.text.reversed().prefix { $0 == " " }.count + 1)
        return CGRect(x: end.maxX + cells * end.width, y: end.minY, width: 0, height: end.height)
    }

    /// One character cell, at a terminal agent prompt; nil elsewhere. Typed
    /// and accepted text moves the suggestion by whole cells, not by the
    /// widths of a proportional font (which jumped until the next read).
    private var terminalCell: CGFloat?
    /// The surface of the last field suggested in.
    private var lastSurface: SurfaceClass?
    /// At a terminal agent prompt: where the caret is, from the keys (the
    /// agent's drawn cursor is invisible to Accessibility), and what the
    /// prompt held at the last read.
    private var promptCaret = PromptCaret()
    private var promptText = ""
    /// While a terminal suggestion is up: the prompt is read again now and
    /// then, since the agent redraws on its own (a sent message clears it).
    private var watchTask: Task<Void, Never>?

    /// How far `typed` moves the caret.
    private func advance(of typed: String, caretHeight: CGFloat) -> CGFloat {
        if let terminalCell { return CGFloat(typed.count) * terminalCell }
        return GhostTextPanel.width(of: typed, caretHeight: caretHeight, field: GhostTextPanel.shared.fieldFont)
    }

    /// A monospaced font whose characters are `cell` wide: terminals report
    /// no font, and the suggestion should look like the text beside it.
    private static func monospaced(cell: CGFloat) -> FieldFont {
        let name = "Menlo-Regular"
        let unit = NSFont(name: name, size: 10).map { ("M" as NSString).size(withAttributes: [.font: $0]).width / 10 } ?? 0.6
        return FieldFont(name: name, size: cell / unit)
    }

    /// Where to draw for `focus`. In a terminal the text after the cursor is
    /// the rest of the screen, not the rest of the line.
    private func placement(for focus: FocusSnapshot, terminal: Bool) -> GhostTextPanel.Placement? {
        TypingPlacement.decide(caretRect: caret(for: focus, terminal: terminal),
                               after: terminal ? nil : focus.after, fieldFrame: focus.fieldFrame)
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
                self.placement(for: $0, terminal: current.request?.surface == .terminal)
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

/// Counts how often learning shaped a suggestion: a habit offered outright,
/// or the prompt given past passages. Logged as numbers, never text.
struct LearningTally {
    private var suggestions = 0, habits = 0, withPassages = 0

    mutating func count(habit: Bool, examples: Int) {
        suggestions += 1
        if habit { habits += 1 }
        if examples > 0 { withPassages += 1 }
        guard suggestions >= 50 else { return }
        PushLogger.log("TypingCoordinator: learning — of \(suggestions) suggestions, \(habits) habits, "
                       + "\(withPassages) with past passages")
        self = LearningTally()
    }
}
