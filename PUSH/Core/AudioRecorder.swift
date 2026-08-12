import Foundation
@preconcurrency import AVFoundation

/// Captures audio from the microphone into a buffer
@MainActor
final class AudioRecorder: @unchecked Sendable {
    static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    private var audioData: Data?
    private var isRecording = false

    // Audio format for Whisper: 16kHz, mono, 16-bit PCM
    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1

    private let sileroVAD = SileroVAD.shared

    // Ordered hand-off from the realtime tap thread to the main actor. An
    // AsyncStream preserves FIFO order; spawning one Task per buffer does not,
    // which could interleave chunks and garble the recording.
    private var sampleContinuation: AsyncStream<[Float]>.Continuation?
    private var drainTask: Task<Void, Never>?

    // Callback for VAD-triggered stop
    var onSilenceDetected: (() -> Void)?

    private init() {}

    // MARK: - Public API

    /// Touch the expensive, lazily-initialised parts of the capture path at
    /// launch so the first hotkey press doesn't pay for them. Nobody dictates
    /// the instant their machine boots, so this cost belongs at startup.
    ///
    /// Deliberately does NOT start the engine: nothing is captured, so the
    /// system microphone indicator stays off.
    func prewarm() async {
        _ = readyEngine()
        PushLogger.log("AudioRecorder: capture path pre-warmed")

        // The VAD's CoreML model otherwise loads on the first press, inside the
        // same window the user is already waiting through.
        await sileroVAD.setup()
    }

    /// The process's one capture engine, built on first use.
    ///
    /// It outlives individual recordings on purpose. Constructing an engine and
    /// querying `inputNode.outputFormat` initialises the input device, which
    /// measured ~0.72s cold and ~0.09s warm — and the earlier prewarm built a
    /// local engine that was released immediately, so the device was torn back
    /// down and the user's first press paid the cold cost anyway. Keeping one
    /// instance means that happens once, at launch.
    private func readyEngine() -> AVAudioEngine {
        if let audioEngine { return audioEngine }
        let engine = AVAudioEngine()
        _ = engine.inputNode.outputFormat(forBus: 0)
        engine.prepare()
        // Rebuild after a device change (mic unplugged, output switched):
        // a stopped engine can otherwise keep reporting the old device's format.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isRecording else { return }
                self.audioEngine = nil
                PushLogger.log("AudioRecorder: audio configuration changed, engine will rebuild")
            }
        }
        audioEngine = engine
        return engine
    }

    func startRecording(withVAD: Bool = false) {
        guard !isRecording else { return }

        PressTiming.mark("startRecording enter")
        audioData = Data()

        let engine = readyEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        PressTiming.mark("inputFormat")

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            PushLogger.log("AudioRecorder: Failed to create output format")
            return
        }

        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
        sampleContinuation = continuation
        // SPIKE: the streaming model consumes audio while you speak. Resetting
        // it here (rather than at engine.start()) guarantees it happens before
        // the first sample is consumed — the AsyncStream buffers until this
        // task is ready, so no leading audio is lost.
        let isStreamingModel = AppState.shared.activeModel.engineType == .parakeetStreaming

        drainTask = Task { [weak self] in
            if isStreamingModel {
                await ParakeetStreamingEngine.shared.beginUtterance()
            }
            for await samples in stream {
                guard let self else { return }
                self.audioData?.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
                await self.sileroVAD.processSamples(samples)
                if isStreamingModel {
                    await ParakeetStreamingEngine.shared.feed(samples)
                }
            }
        }

        // @Sendable is load-bearing: without it this closure inherits the
        // enclosing @MainActor isolation, and AVFoundation invokes it on the
        // realtime audio thread — which traps under -enable-actor-data-race-checks
        // and is a latent data race in release builds.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
            let source = converter.flatMap {
                Self.convert(buffer: buffer, converter: $0, outputFormat: outputFormat)
            } ?? buffer
            guard let channelData = source.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(source.frameLength)))
            continuation.yield(samples)
        }

        do {
            try engine.start()
            PressTiming.mark("engine.start")
            isRecording = true

            MediaController.shared.beginDictation(behavior: AppState.shared.mediaBehavior)
            PressTiming.mark("beginDictation")

            // Always run Silero VAD: gates transcription in hotkey mode,
            // auto-stops recording in wake word mode.
            Task {
                await sileroVAD.setup()
                await sileroVAD.reset()
                if withVAD {
                    await sileroVAD.configure { [weak self] in
                        Task { @MainActor in self?.onSilenceDetected?() }
                    }
                }
            }

            PushLogger.log("AudioRecorder: Started recording\(withVAD ? " with auto-stop VAD" : "")")
            PressTiming.mark("recording started")
            PressTiming.end()
        } catch {
            PushLogger.log("AudioRecorder: Failed to start engine: \(error)")
            continuation.finish()
            sampleContinuation = nil
            drainTask = nil
        }
    }

    func stopRecording() async -> Data? {
        guard isRecording else { return nil }

        // Release the microphone FIRST — nothing about restoring other apps'
        // audio should delay giving the mic back.
        // Stopped, not released: holding the engine keeps the input device
        // initialised so the next press doesn't re-pay for waking it.
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        isRecording = false

        // Unconditional and synchronous: a no-op unless we actually changed
        // something, so it stays correct even if the setting changed mid-take.
        MediaController.shared.endDictation()

        // Drain buffered samples so the tail of speech isn't dropped.
        sampleContinuation?.finish()
        sampleContinuation = nil
        await drainTask?.value
        drainTask = nil

        let result = audioData
        audioData = nil

        PushLogger.log("AudioRecorder: Stopped recording, captured \(result?.count ?? 0) bytes")
        return result
    }

    // MARK: - Private

    private nonisolated static func convert(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            PushLogger.log("AudioRecorder: Conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }
}
