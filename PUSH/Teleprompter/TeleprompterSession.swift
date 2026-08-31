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
    /// The model to put back when the take ends. Nil if we never swapped.
    private var restoreModel: AppState.WhisperModel?
    private var ticker: Task<Void, Never>?
    /// Position at the last timed step, for the no-voice fallback.
    private var timedCursor: Double = 0
    private var lastTick: TimeInterval = 0

    private init() {}

    // MARK: - Readiness

    static var readiness: Readiness {
        ParakeetStreamingEngine.isModelDownloaded() ? .ready : .needsDownload
    }

    var tokenCount: Int { aligner.tokens.count }

    func text(at index: Int) -> String? { aligner.text(at: index) }

    /// The exact string the aligner tokenized.
    ///
    /// The view must lay *this* out rather than its own copy of the settings
    /// text: token ranges are `String.Index` values, which are only meaningful
    /// against the instance they came from.
    var script: String { aligner.script }

    func tokenRange(at index: Int) -> Range<String.Index>? {
        guard aligner.tokens.indices.contains(index) else { return nil }
        return aligner.tokens[index].range
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

    private func consume(partial: String) {
        guard isRunning else { return }
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
