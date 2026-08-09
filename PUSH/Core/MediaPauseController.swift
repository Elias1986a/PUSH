import Foundation

/// Pauses/resumes system media playback around dictation, so background
/// audio doesn't bleed into the recording. Uses injected closures so the
/// state machine (this type) can be tested without touching the real
/// MediaRemote framework — see `MediaRemoteBridge` for the production wiring.
@MainActor
final class MediaPauseController {
    static let shared = MediaPauseController()

    static let kMRPlay = 0
    static let kMRPause = 1

    private let sendCommand: (Int) -> Bool
    private let fetchRate: (@escaping (Double?) -> Void) -> Void

    private var didPauseMedia = false
    private var pauseCheckTask: Task<Void, Never>?

    convenience init() {
        if let bridge = MediaRemoteBridge.load() {
            self.init(sendCommand: bridge.sendCommand, fetchRate: bridge.fetchRate)
        } else {
            self.init(sendCommand: { _ in false }, fetchRate: { completion in completion(nil) })
        }
    }

    init(sendCommand: @escaping (Int) -> Bool, fetchRate: @escaping (@escaping (Double?) -> Void) -> Void) {
        self.sendCommand = sendCommand
        self.fetchRate = fetchRate
    }

    /// Fire-and-forget: never blocks the caller (AudioRecorder.startRecording
    /// must not gain latency from this). Guarded on `pauseCheckTask` (not just
    /// `didPauseMedia`) so a second call while the first check is still
    /// in-flight doesn't race it and issue a duplicate pause.
    func pauseIfPlaying() {
        guard !didPauseMedia, pauseCheckTask == nil else { return }
        pauseCheckTask = Task { [weak self] in
            guard let self else { return }
            let rate = await self.currentRate()
            guard !Task.isCancelled, rate == 1.0 else { return }
            self.didPauseMedia = true
            _ = self.sendCommand(Self.kMRPause)
        }
    }

    /// Only resumes playback if `pauseIfPlaying()` actually paused something —
    /// never starts media that was already stopped/paused before dictation.
    func resumeIfWePaused() async {
        await pauseCheckTask?.value
        pauseCheckTask = nil
        guard didPauseMedia else { return }
        didPauseMedia = false
        _ = sendCommand(Self.kMRPlay)
        // No-op against the real synchronous MediaRemote bridge; exists so
        // test doubles that record calls via a detached Task get a chance
        // to run before assertions check them.
        await Task.yield()
    }

    private func currentRate() async -> Double? {
        await withCheckedContinuation { continuation in
            fetchRate { rate in continuation.resume(returning: rate) }
        }
    }
}
