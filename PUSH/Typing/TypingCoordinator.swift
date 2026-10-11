import AppKit
import PUSHCore

/// Where a suggestion is drawn. Pure, so it is pinned by tests.
enum TypingPlacement {
    static func decide(caretRect: CGRect?, after: String?, fieldFrame: CGRect?) -> GhostTextPanel.Placement? {
        let restOfLine = (after ?? "").prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        if let caretRect, restOfLine.isEmpty { return .inline(caret: caretRect) }
        if let fieldFrame { return .card(below: fieldFrame) }
        if let caretRect { return .card(below: caretRect) }
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
                refreshPlacement()
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
            refreshPlacement()
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
        guard stamp == keystrokes, mayRun, let focus, !focus.isSecure,
              !TypingExclusions.isExcluded(bundleID: focus.bundleID),
              focus.pid != ProcessInfo.processInfo.processIdentifier else { return }
        let surface = SurfaceClass.classify(bundleID: focus.bundleID)
        guard surface != .terminal else { return }          // terminals come with Task 4.1d

        let before = focus.before ?? buffer.text
        guard before.contains(where: { !$0.isWhitespace }) else { return }
        guard let placement = TypingPlacement.decide(
            caretRect: focus.caretRect, after: focus.after, fieldFrame: focus.fieldFrame) else { return }

        let heal = TokenHealing.split(before)
        let context = TypingContext(
            before: heal.prompt, after: focus.after,
            surfaceLine: SurfaceLine.render(surface: surface, appName: focus.appName, windowTitle: focus.windowTitle,
                                            url: focus.url, placeholder: focus.placeholder),
            userName: NSFullUserName().split(separator: " ").first.map(String.init))
        let prompt = TypingPrompt.render(context)
        let length = AppState.shared.typingLength
        let grammar = TokenHealing.grammar(forcing: heal.forced)

        generationTask?.cancel()
        generationTask = Task {
            var raw = ""
            do {
                for try await piece in await LlamaEngine.shared.complete(
                    prompt: prompt, maxTokens: length.maxTokens, grammar: grammar) {
                    guard stamp == keystrokes, !Task.isCancelled else { return }
                    raw += piece
                    guard let text = TokenHealing.strip(raw, forced: heal.forced),
                          let clean = SuggestionText.clean(text, maxWords: length.words.upperBound) else { continue }
                    show(length.trim(clean), at: placement)
                }
            } catch {
                PushLogger.log("TypingCoordinator: generation failed: \(error)")
            }
        }
    }

    private func show(_ text: String, at placement: GhostTextPanel.Placement) {
        guard mayRun, !text.isEmpty else { return }
        shown = Shown(text: text, placement: placement)
        GhostTextPanel.shared.show(text, at: placement)
        TypingKeyTap.shared.setSuggestionVisible(true)
    }

    /// The caret moved (typed into or accepted part of the suggestion): read
    /// it again and redraw what is left.
    private func refreshPlacement() {
        let stamp = keystrokes
        Task {
            let focus = await Task.detached(priority: .userInitiated) { FocusReader.read() }.value
            guard stamp == keystrokes, let current = shown else { return }
            let placement = focus.flatMap {
                TypingPlacement.decide(caretRect: $0.caretRect, after: $0.after, fieldFrame: $0.fieldFrame)
            } ?? current.placement
            shown?.placement = placement
            GhostTextPanel.shared.show(current.text, at: placement)
        }
    }
}
