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

    static func isExcluded(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return prefixes.contains { id.hasPrefix($0) }
    }
}

/// Runs Type: keystrokes in, a suggestion out. Debounces, reads the field off
/// the main thread, builds the prompt, streams from the engine, draws the
/// suggestion, and types it on accept. Never logs text.
@MainActor
final class TypingCoordinator {
    static let shared = TypingCoordinator()

    static let debounce: Duration = .milliseconds(150)

    private struct Shown {
        var text: String
        var placement: GhostTextPanel.Placement
    }

    private var active = false
    private var buffer = KeystrokeBuffer()
    private var keystrokes = 0          // bumps on every user key; stale work compares against it
    private var debounceTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var shown: Shown?
    /// The field the keystroke buffer belongs to.
    private var bufferElement: Int?

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
        } else {
            TypingKeyTap.shared.stop()
            cancelWork()
            hide()
        }
    }

    /// Dictation or the teleprompter started: get out of the way.
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
        case .dismiss:
            cancelWork()
            hide()
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
        let chunk = whole ? current.text : SuggestionText.nextChunk(of: current.text)
        KeystrokeTyper.type(chunk)
        if let rest = SuggestionText.remainder(of: current.text, afterTyping: chunk) {
            shown?.text = rest
            advanceCaret(by: chunk)
            refreshPlacement(after: .milliseconds(300))
        } else {
            hide()
            scheduleSuggestion()
        }
    }

    // MARK: - Suggesting

    private func cancelWork() {
        debounceTask?.cancel()
        generationTask?.cancel()
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
    }

    private func suggest(stamp: Int) async {
        guard mayRun else { return }
        let focus = await Task.detached(priority: .userInitiated) { FocusReader.read() }.value
        guard stamp == keystrokes, mayRun, let focus, !focus.isSecure, focus.isTextInput,
              !TypingExclusions.isExcluded(bundleID: focus.bundleID),
              focus.pid != ProcessInfo.processInfo.processIdentifier else { return }
        let surface = SurfaceClass.classify(bundleID: focus.bundleID)
        guard surface != .code || AppState.shared.typingInCodeEditors else { return }

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
            guard let line = TerminalLine.parse(textBeforeCaret: before), line.kind == .agentPrompt else { return }
            before = line.text
            surfaceLine = SurfaceLine.render(surface: .chat, appName: focus.appName, windowTitle: focus.windowTitle,
                                             url: nil, placeholder: nil)
        }
        guard SuggestionText.shouldSuggest(before: before, after: surface == .terminal ? nil : focus.after) else { return }
        guard let placement = TypingPlacement.decide(
            caretRect: focus.caretRect, after: focus.after, fieldFrame: focus.fieldFrame) else { return }

        let heal = TokenHealing.split(before)
        let context = TypingContext(
            before: heal.prompt, after: surface == .terminal ? nil : focus.after,
            surfaceLine: surfaceLine,
            userName: NSFullUserName().split(separator: " ").first.map(String.init))
        let prompt = TypingPrompt.render(context)
        let length = AppState.shared.typingLength
        let maxWords = length.maxWords(for: before)

        startGeneration(prompt: prompt, forced: heal.forced, before: before, length: length, maxWords: maxWords,
                        placement: placement, surface: surface, stamp: stamp, wordBoundary: false)
    }

    /// Streams one suggestion. When the model glues letters onto the word at
    /// the caret, the joined word must be a real one ("appreci" + "ate");
    /// otherwise ("Hello" + "u") it asks again with a word break forced after
    /// the word — Cotabby checks the caret word with the spell checker too.
    private func startGeneration(prompt: String, forced: String, before: String, length: LengthPreset,
                                 maxWords: Int, placement: GhostTextPanel.Placement, surface: SurfaceClass, stamp: Int,
                                 wordBoundary: Bool) {
        generationTask?.cancel()
        generationTask = Task {
            var raw = ""
            var judged = wordBoundary || forced.isEmpty
            let grammar = TokenHealing.grammar(forcing: forced, wordBoundary: wordBoundary)
            @MainActor func retryWithBoundary() {
                startGeneration(prompt: prompt, forced: forced, before: before, length: length, maxWords: maxWords,
                                placement: placement, surface: surface, stamp: stamp, wordBoundary: true)
            }
            /// False when the attempt was abandoned for a retry.
            @MainActor func consider(final: Bool) -> Bool {
                guard let text = TokenHealing.strip(raw, forced: forced) else { return true }
                if !judged {
                    if let word = TokenHealing.gluedWord(forced: forced, continuation: text) {
                        let wordEnded = text.contains { !($0.isLetter || $0 == "'" || $0 == "’") }
                        guard wordEnded || final else { return true }     // wait for the whole word
                        judged = true
                        if !Self.isRealWord(word) {
                            retryWithBoundary()
                            return false
                        }
                    } else {
                        judged = true
                    }
                }
                guard let clean = SuggestionText.clean(text, maxWords: maxWords) else { return true }
                guard let polished = SuggestionText.polish(length.trim(clean), before: before),
                      SuggestionText.matchesScript(polished, before: before),
                      !SuggestionText.isUnwanted(polished, before: before),
                      // Near-empty page: the one word must be a real one.
                      maxWords > 1 || Self.realWords(polished) else {
                    // A later piece turned it unacceptable: take down what an
                    // earlier piece showed (", " before "I'm a 17…") and stop.
                    hide()
                    generationTask?.cancel()
                    return false
                }
                show(polished, at: placement, surface: surface)
                return true
            }
            do {
                for try await piece in await LlamaEngine.shared.complete(
                    prompt: prompt, maxTokens: length.maxTokens, grammar: grammar) {
                    guard stamp == keystrokes, !Task.isCancelled else { return }
                    raw += piece
                    if !consider(final: false) { return }
                }
                guard stamp == keystrokes, !Task.isCancelled else { return }
                _ = consider(final: true)
            } catch {
                PushLogger.log("TypingCoordinator: generation failed: \(error)")
            }
        }
    }

    private static func realWords(_ text: String) -> Bool {
        text.split { !($0.isLetter || $0 == "'" || $0 == "’") }.allSatisfy { isRealWord(String($0)) }
    }

    private static func isRealWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }

    private func show(_ text: String, at placement: GhostTextPanel.Placement, surface: SurfaceClass) {
        guard mayRun, !text.isEmpty else { return }
        let appearing = shown == nil
        // → in terminals, where Tab is the shell's completion.
        if appearing {
            TypingKeyTap.shared.setKeys(nextWord: AcceptKeyResolver.nextWordKey(surface: surface),
                                        whole: AcceptKeyResolver.wholeSuggestionKey(layout: KeyboardLayoutMap.current()))
        }
        // What fits on screen is the suggestion: accepting never types words
        // the user could not see.
        guard let visible = GhostTextPanel.shared.show(text, at: placement) else {
            if appearing { hide() }
            return
        }
        shown = Shown(text: visible, placement: placement)
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
            let focus = await Task.detached(priority: .userInitiated) { FocusReader.read() }.value
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
