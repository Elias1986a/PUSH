import Foundation
import FluidAudio

/// Streaming VAD using FluidAudio's Silero VAD model (CoreML/Neural Engine).
/// Processes audio in 256ms chunks and fires onSilenceDetected after 1s of silence
/// following detected speech, replacing the previous RMS amplitude threshold approach.
actor SileroVAD {
    static let shared = SileroVAD()

    private var manager: VadManager?
    private var streamState: VadStreamState = .initial()
    private var pendingSamples: [Float] = []
    private(set) var isReady = false

    private var speechDetected = false
    private var gracePeriodEnds: Date = .distantPast

    // Match the previous 1.0s silence duration behaviour
    private let segConfig = VadSegmentationConfig(minSilenceDuration: 1.0)

    private var silenceCallback: (() -> Void)?

    private init() {}

    // MARK: - Public API

    func setup() async {
        guard !isReady else { return }
        do {
            let m = try await VadManager(config: VadConfig(defaultThreshold: 0.5))
            manager = m
            streamState = await m.makeStreamState()
            isReady = true
            PushLogger.log("SileroVAD: ✅ Ready (Silero VAD via CoreML/ANE)")
        } catch {
            PushLogger.log("SileroVAD: ❌ Setup failed: \(error)")
        }
    }

    func configure(onSilenceDetected: @escaping () -> Void) {
        silenceCallback = onSilenceDetected
    }

    /// Whether any speech was detected since the last reset. Used to gate hotkey transcription.
    func speechWasDetected() -> Bool { speechDetected }

    func reset(gracePeriod: TimeInterval = 2.0) async {
        pendingSamples = []
        if let m = manager { streamState = await m.makeStreamState() }
        speechDetected = false
        silenceCallback = nil
        gracePeriodEnds = Date().addingTimeInterval(gracePeriod)
    }

    func processSamples(_ samples: [Float]) async {
        guard isReady, let manager = manager else { return }
        pendingSamples.append(contentsOf: samples)
        while pendingSamples.count >= VadManager.chunkSize {
            let chunk = Array(pendingSamples.prefix(VadManager.chunkSize))
            pendingSamples.removeFirst(VadManager.chunkSize)
            await processChunk(chunk, using: manager)
        }
    }

    // MARK: - Private

    private func processChunk(_ chunk: [Float], using manager: VadManager) async {
        guard let result = try? await manager.processStreamingChunk(
            chunk, state: streamState, config: segConfig
        ) else { return }

        streamState = result.state

        guard let event = result.event else { return }

        if event.isStart {
            speechDetected = true
            PushLogger.log("SileroVAD: Speech start (p=\(String(format: "%.2f", result.probability)))")
        } else if event.isEnd, speechDetected, Date() >= gracePeriodEnds {
            PushLogger.log("SileroVAD: Silence detected → stopping")
            let callback = silenceCallback
            Task { @MainActor in callback?() }
        }
    }
}
