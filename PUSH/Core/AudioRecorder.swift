import Foundation
import PUSHCore
@preconcurrency import AVFoundation

/// Captures audio from the microphone into a buffer
@MainActor
final class AudioRecorder: @unchecked Sendable {
    static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    private var engineBuild: Task<AVAudioEngine, Never>?
    private var audioData: Data?
    private var isRecording = false
    /// Set for the window between a press and the engine being ready, so a
    /// second press can't kick off a parallel start.
    private var isStarting = false

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
        _ = await readyEngine()
        PushLogger.log("AudioRecorder: capture path pre-warmed")

        // The VAD's CoreML model otherwise loads on the first press, inside the
        // same window the user is already waiting through.
        await sileroVAD.setup()
    }

    /// The process's one capture engine, built on first use.
    ///
    /// It outlives individual recordings on purpose. Constructing an engine and
    /// querying `inputNode.outputFormat` initialises the input device, which
    /// measured ~4s cold and ~0.09s warm — and an earlier prewarm built a local
    /// engine that was released immediately, so the device was torn back down
    /// and the user's first press paid the cold cost anyway.
    ///
    /// The build is held as a Task so a press landing mid-warmup joins the one
    /// already running instead of starting a second: doing that cost 1336ms of
    /// blocked main thread while the background build finished moments later.
    /// Nothing here runs on the main thread — holding it that long is what gets
    /// the hotkey's event tap disabled by the system.
    private func readyEngine() async -> AVAudioEngine {
        if let audioEngine { return audioEngine }
        let preferredUID = AppState.shared.inputDeviceUID
        let build = engineBuild ?? {
            let task = Task.detached(priority: .userInitiated) { Self.buildEngine(preferredUID: preferredUID) }
            engineBuild = task
            return task
        }()
        let engine = await build.value
        engineBuild = nil
        // Another caller may have adopted it while this one was suspended.
        if let audioEngine { return audioEngine }
        adopt(engine)
        return engine
    }

    /// Initialising the input device is the expensive part and needs no main
    /// thread, so this is callable from anywhere.
    private nonisolated static func buildEngine(preferredUID: String?) -> AVAudioEngine {
        // Timed in parts: this is the "deaf window" on a cold press — the seconds
        // between the key going down and the mic actually hearing anything — so
        // it matters which step owns it, not just the total.
        let t0 = Date()
        let engine = AVAudioEngine()
        let t1 = Date()
        let input = engine.inputNode
        let t2 = Date()
        // Before the format query, which is the call that actually initialises
        // the device — binding afterwards would wake the default microphone
        // first and then switch, paying the expensive part twice.
        bind(input: input, toUID: preferredUID)
        _ = input.outputFormat(forBus: 0)
        let t3 = Date()
        engine.prepare()
        let t4 = Date()
        PushLogger.log(String(
            format: "AudioRecorder: engine build — alloc %.0fms, inputNode %.0fms, format %.0fms, prepare %.0fms",
            t1.timeIntervalSince(t0) * 1000,
            t2.timeIntervalSince(t1) * 1000,
            t3.timeIntervalSince(t2) * 1000,
            t4.timeIntervalSince(t3) * 1000))
        return engine
    }

    /// Point the engine's input at the user's chosen microphone.
    ///
    /// Silently keeps the system default when the choice is nil (the default
    /// preference) or when the device is not attached right now — a USB
    /// interface that is simply unplugged is an ordinary state, not an error
    /// to interrupt someone mid-press with. The log line is the record.
    private nonisolated static func bind(input: AVAudioInputNode, toUID uid: String?) {
        guard let uid else { return }
        guard let deviceID = AudioInputDevices.deviceID(forUID: uid) else {
            PushLogger.log("AudioRecorder: preferred input device is not attached, using the system default")
            return
        }
        do {
            try input.auAudioUnit.setDeviceID(deviceID)
            PushLogger.log("AudioRecorder: input bound to the selected device")
        } catch {
            PushLogger.log("AudioRecorder: could not bind the selected input device (\(error.localizedDescription)), using the system default")
        }
    }

    /// Drop the engine so the next press rebuilds it against the new device.
    ///
    /// The device is bound once, when the engine is built, so a live engine
    /// would keep using the old microphone until something else happened to
    /// invalidate it. Deliberately does nothing mid-recording: swapping the
    /// device under a take in progress would truncate it, and the next press
    /// is moments away.
    func inputDeviceDidChange() {
        guard !isRecording else {
            PushLogger.log("AudioRecorder: input device changed mid-recording, applying it on the next press")
            return
        }
        audioEngine = nil
        engineBuild = nil
        PushLogger.log("AudioRecorder: input device changed, engine will rebuild")
        // Re-pay the device-init cost now rather than on the user's next press;
        // this is the same reason `prewarm()` exists.
        Task { _ = await readyEngine() }
    }

    private func adopt(_ engine: AVAudioEngine) {
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
    }

    /// What the capture is for. Dictation captures a short utterance and keeps
    /// the bytes to transcribe on release; the teleprompter runs for the length
    /// of a take and only ever consumes partials.
    enum CaptureMode {
        case dictation
        /// Minutes, not seconds. Keeps no buffer, and periodically resets the
        /// ASR utterance so a long take doesn't accumulate context nobody reads.
        case continuous
    }

    /// How long a `.continuous` segment runs before the streaming utterance is
    /// reset. The prompter's aligner matches on the *trailing* few tokens
    /// against a window near its cursor, so a partial that restarts from empty
    /// re-matches immediately — resetting costs nothing and bounds the context.
    private static let continuousSegment: TimeInterval = 15

    func startRecording(withVAD: Bool = false, mode: CaptureMode = .dictation) async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        PressTiming.mark("startRecording enter")

        // Suspends only if a press beat the launch warmup. Awaiting rather than
        // building inline keeps the main thread free, so the pill keeps animating
        // and the event tap stays alive while the device comes up.
        let engine = await readyEngine()
        PressTiming.mark("engine ready")

        // The key can be released while the capture path is still warming; don't
        // strand a recording nobody is waiting for. Continuous capture has no
        // key behind it, so there is no press to have ended.
        if mode == .dictation {
            guard AppState.shared.isListening else {
                PushLogger.log("AudioRecorder: press ended before the capture path was ready")
                return
            }
        }

        // Nil in continuous mode: the prompter reads partials as they arrive and
        // never transcribes a buffer, so retaining one would cost ~4MB/minute to
        // hold bytes nobody reads.
        audioData = mode == .dictation ? Data() : nil
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

        let segmentSamples = Int(sampleRate * Self.continuousSegment)

        drainTask = Task { [weak self] in
            if isStreamingModel {
                await ParakeetStreamingEngine.shared.beginUtterance()
            }
            var samplesThisSegment = 0
            for await samples in stream {
                guard let self else { return }
                // Before the VAD await below, not after: this is what the pill's
                // waveform draws, and it should reflect the buffer that just
                // arrived rather than the one before it. The arithmetic is a
                // sum over ~1300 floats — cheaper than the CoreML inference it
                // is sitting in front of.
                AudioLevelMonitor.shared.consume(samples)
                self.audioData?.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
                // Continuous capture has nothing to auto-stop, and Silero is a
                // CoreML inference per buffer — not worth running for the length
                // of a take to answer a question nobody asked.
                if mode == .dictation {
                    await self.sileroVAD.processSamples(samples)
                }
                if isStreamingModel {
                    await ParakeetStreamingEngine.shared.feed(samples)

                    if mode == .continuous {
                        samplesThisSegment += samples.count
                        if samplesThisSegment >= segmentSamples {
                            await ParakeetStreamingEngine.shared.beginUtterance()
                            samplesThisSegment = 0
                        }
                    }
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
            AppState.shared.isCapturing = true

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
        AppState.shared.isCapturing = false
        // The waveform reads the level without checking isCapturing, so silence
        // has to be published here rather than left at the last buffer's value.
        AudioLevelMonitor.shared.reset()

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
