import AppKit
import Combine
import Foundation
import PUSHCore

/// Runs a teleprompter take: borrows the streaming engine, feeds its partials to
/// the aligner, and publishes where on the script the speaker is.
///
/// Separate from `AppState` on purpose. The prompter is a second feature that
/// happens to reuse dictation's plumbing, not a mode of dictation, and keeping
/// its state here means dictation cannot regress when this changes.
@MainActor
final class TeleprompterSession: ObservableObject {
    static let shared = TeleprompterSession()

    /// Whether voice-following can run right now, and if not, why.
    enum Readiness: Equatable {
        /// The streaming model is on disk. Note this is true for anyone who
        /// already has Parakeet Unified: the streaming encoder ships inside the
        /// same bundle, so most users need no download.
        case ready
        /// Voice-following needs the Parakeet bundle fetched first. The prompter
        /// still opens and runs on the timer meanwhile.
        case needsDownload
    }

    // MARK: - Published state

    @Published private(set) var isRunning = false
    @Published private(set) var position = ScriptAligner.Position(cursor: 0, state: .idle)
    /// False when running on the timer instead — either because the model isn't
    /// downloaded, or because the user turned voice-following off.
    @Published private(set) var isFollowingVoice = false

    // MARK: - Settings

    /// Pace for the timed fallback, in words per minute.
    var timedWordsPerMinute: Double = 150

    // MARK: - Private state

    private var aligner = ScriptAligner(script: "")
    /// Line breaks for the script currently on screen. See `script`.
    @Published private(set) var layout = ScriptLayout(script: "", font: .systemFont(ofSize: 12), width: 1)
    private var cancellables = Set<AnyCancellable>()
    /// The model to put back when the take ends. Nil if we never swapped.
    private var restoreModel: AppState.WhisperModel?
    private var ticker: Task<Void, Never>?
    /// Position at the last timed step, for the no-voice fallback.
    private var timedCursor: Double = 0
    private var lastTick: TimeInterval = 0

    private init() {
        // Both settings change the line breaks, so both have to rebuild them.
        let settings = TeleprompterState.shared
        settings.$size.combineLatest(settings.$script)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.rebuildLayout() }
            .store(in: &cancellables)
    }

    // MARK: - Readiness

    static var readiness: Readiness {
        ParakeetStreamingEngine.isModelDownloaded() ? .ready : .needsDownload
    }

    var tokenCount: Int { aligner.tokens.count }

    func text(at index: Int) -> String? { aligner.text(at: index) }

    /// The exact string the aligner tokenized.
    ///
    /// Laid out here rather than in the view, for two reasons: token ranges are
    /// `String.Index` values that only mean anything against the instance they
    /// came from, so one owner keeps them honest; and the view's body runs on
    /// every one of the 20 position updates a second, which is no place to
    /// re-run CoreText over the whole script.
    var script: String { aligner.script }

    func tokenRange(at index: Int) -> Range<String.Index>? {
        guard aligner.tokens.indices.contains(index) else { return nil }
        return aligner.tokens[index].range
    }

    /// The display line the speaker is on, against the same line breaks the
    /// view draws.
    var currentLine: Int {
        guard isRunning, !layout.lines.isEmpty else { return 0 }
        let token = Int(position.cursor.rounded())
        guard let range = tokenRange(at: token) else { return 0 }
        return layout.lineIndex(containing: range.lowerBound)
    }

    /// Rebuild the line breaks. Driven by the settings that change them, and by
    /// the start of a take.
    func rebuildLayout() {
        let settings = TeleprompterState.shared
        let text = isRunning ? aligner.script : settings.script
        layout = ScriptLayout(
            script: text,
            font: NSFont.systemFont(
                ofSize: settings.size.fontSize, weight: .semibold, width: .condensed),
            width: settings.size.width
        )
    }

    // MARK: - Manual control

    /// Move by whole display lines — what the arrow keys do.
    ///
    /// A correction, not a scroll offset: it moves where the prompter believes
    /// the speaker is, so voice-following carries on from the corrected place
    /// instead of yanking back to its own guess.
    func nudge(lines: Int) {
        guard isRunning, !layout.lines.isEmpty else { return }
        let target = min(max(currentLine + lines, 0), layout.lines.count - 1)
        let token = firstToken(onLine: target)

        if isFollowingVoice {
            aligner.seek(to: token, at: Date().timeIntervalSinceReferenceDate)
            position = aligner.tick(at: Date().timeIntervalSinceReferenceDate)
        } else {
            timedCursor = Double(token)
            position = ScriptAligner.Position(cursor: timedCursor, state: .lost)
        }
    }

    /// First token starting at or after the given line's first character.
    private func firstToken(onLine line: Int) -> Int {
        guard layout.lines.indices.contains(line) else { return 0 }
        let start = layout.lines[line].range.lowerBound
        return aligner.tokens.firstIndex { $0.range.lowerBound >= start }
            ?? max(aligner.tokens.count - 1, 0)
    }

    /// Nudge the timed pace. Only meaningful when not following your voice —
    /// when it is, the pace is measured from you rather than dialled in.
    func adjustSpeed(by delta: Double) {
        let settings = TeleprompterState.shared
        settings.wordsPerMinute = min(max(settings.wordsPerMinute + delta, 60), 400)
        timedWordsPerMinute = settings.wordsPerMinute
    }

    // MARK: - Lifecycle

    /// Begin a take. `followVoice` false runs the timer instead, which is also
    /// what happens when the model isn't available.
    func start(script: String, followVoice: Bool = true) async {
        guard !isRunning else { return }

        aligner = ScriptAligner(script: script)
        timedCursor = 0
        position = ScriptAligner.Position(cursor: 0, state: .idle)
        isRunning = true
        hasHeardPartial = false
        rebuildLayout()

        timedWordsPerMinute = TeleprompterState.shared.wordsPerMinute
        let canFollow = followVoice && Self.readiness == .ready
        isFollowingVoice = canFollow

        if canFollow {
            await beginVoiceFollowing()
        }

        lastTick = Date().timeIntervalSinceReferenceDate
        startTicker()
        PushLogger.log("Teleprompter: started (\(aligner.tokens.count) tokens, voice: \(canFollow))")
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        ticker?.cancel()
        ticker = nil

        if isFollowingVoice {
            await endVoiceFollowing()
        }
        isFollowingVoice = false
        PushLogger.log("Teleprompter: stopped")
    }

    // MARK: - Voice following

    private func beginVoiceFollowing() async {
        let current = AppState.shared.activeModel
        if current.engineType != .parakeetStreaming {
            // Only ModelLoader activates models (CLAUDE.md). Remember what to
            // put back so a take never silently changes the dictation engine.
            restoreModel = current
            try? await ModelLoader.activate(.parakeetStreaming)
        }

        // Borrow the engine's single partial slot for the length of the take.
        await ParakeetStreamingEngine.shared.setOnPartial { [weak self] partial in
            Task { @MainActor in
                self?.consume(partial: partial)
            }
        }

        await AudioRecorder.shared.startRecording(mode: .continuous)
    }

    private func endVoiceFollowing() async {
        _ = await AudioRecorder.shared.stopRecording()
        await ModelLoader.installDictationPartialHandler()

        if let restoreModel {
            try? await ModelLoader.activate(restoreModel)
            self.restoreModel = nil
        }
    }

    /// Whether any partial has arrived this take, so the first one can be
    /// logged. Silence here used to be indistinguishable from a working take.
    private var hasHeardPartial = false

    private func consume(partial: String) {
        guard isRunning else { return }
        if !hasHeardPartial {
            hasHeardPartial = true
            // Length only, never the text (privacy).
            PushLogger.log("Teleprompter: first partial received (\(partial.count) chars)")
        }
        position = aligner.consume(partial: partial, at: Date().timeIntervalSinceReferenceDate)
    }

    // MARK: - Ticking

    /// 20Hz. Enough for the spring to look continuous, and two orders of
    /// magnitude below driving the UI from the audio tap — which is how
    /// NotchPrompter does it, and how PUSH's event tap gets disabled.
    private static let tickInterval = Duration.milliseconds(50)

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self, self.isRunning else { return }
                self.step()
            }
        }
    }

    private func step() {
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = now - lastTick
        lastTick = now

        guard isFollowingVoice else {
            // Timed fallback: a plain crawl at the configured pace.
            timedCursor = min(
                timedCursor + timedWordsPerMinute / 60.0 * elapsed,
                Double(max(aligner.tokens.count - 1, 0))
            )
            position = ScriptAligner.Position(cursor: timedCursor, state: .lost)
            return
        }
        position = aligner.tick(at: now)
    }
}
