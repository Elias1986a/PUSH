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

    func startRecording(withVAD: Bool = false) {
        guard !isRecording else { return }

        audioData = Data()
        audioEngine = AVAudioEngine()

        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

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
        drainTask = Task { [weak self] in
            for await samples in stream {
                guard let self else { return }
                self.audioData?.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
                await self.sileroVAD.processSamples(samples)
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let source = converter.flatMap {
                Self.convert(buffer: buffer, converter: $0, outputFormat: outputFormat)
            } ?? buffer
            guard let channelData = source.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(source.frameLength)))
            continuation.yield(samples)
        }

        do {
            try engine.start()
            isRecording = true

            if AppState.shared.pauseMediaWhileDictating {
                MediaPauseController.shared.pauseIfPlaying()
            }

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
        } catch {
            PushLogger.log("AudioRecorder: Failed to start engine: \(error)")
            continuation.finish()
            sampleContinuation = nil
            drainTask = nil
        }
    }

    func stopRecording() async -> Data? {
        guard isRecording else { return nil }

        // Unconditional (unlike the pauseMediaWhileDictating-gated pause call
        // above): a no-op unless we actually paused something, so this stays
        // correct even if the setting is toggled off mid-recording.
        await MediaPauseController.shared.resumeIfWePaused()

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

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
