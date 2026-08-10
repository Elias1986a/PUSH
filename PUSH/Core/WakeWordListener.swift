import Foundation
@preconcurrency import AVFoundation

/// Continuously listens for a wake word using Whisper, then triggers recording with VAD
@MainActor
final class WakeWordListener: @unchecked Sendable {
    static let shared = WakeWordListener()

    private var audioEngine: AVAudioEngine?
    private var isListening = false
    private var audioBuffer: Data = Data()
    private var checkTimer: Timer?
    private var sampleContinuation: AsyncStream<[Float]>.Continuation?
    private var drainTask: Task<Void, Never>?

    // Configuration
    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1
    private let bufferDuration: TimeInterval = 1.5 // Keep last 1.5 seconds (faster detection)
    private let checkInterval: TimeInterval = 0.3 // Check every 0.3 seconds (more responsive)

    // Audio level pre-filtering - only run Whisper when speech detected
    private let speechThreshold: Float = 0.015 // RMS threshold to detect speech
    private var recentAudioLevels: [Float] = []
    private var hasSpeechInBuffer = false

    // Prevent concurrent Whisper calls and duplicate detections
    private var isCheckingWakeWord = false
    private var isPaused = false
    private var lastDetectionTime: Date?
    private let detectionCooldown: TimeInterval = 2.0 // Wait 2 seconds after detection before checking again

    // Callback when wake word detected
    var onWakeWordDetected: (() -> Void)?

    private init() {}

    // MARK: - Public API

    func startListening() {
        guard !isListening else { return }
        guard AppState.shared.wakeWordEnabled else { return }

        PushLogger.log("WakeWordListener: Starting wake word detection")

        audioBuffer = Data()
        recentAudioLevels = []
        hasSpeechInBuffer = false
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
            PushLogger.log("WakeWordListener: Failed to create output format")
            return
        }

        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        // Ordered hand-off from the realtime tap thread to the main actor.
        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
        sampleContinuation = continuation
        drainTask = Task { [weak self] in
            for await samples in stream {
                guard let self else { return }
                self.appendSamples(samples)
            }
        }

        // @Sendable is load-bearing: without it this closure inherits the
        // enclosing @MainActor isolation, and AVFoundation invokes it on the
        // realtime audio thread — which traps under -enable-actor-data-race-checks
        // and is a latent data race in release builds.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
            guard let converter = converter,
                  let converted = Self.convert(buffer: buffer, converter: converter, outputFormat: outputFormat),
                  let channelData = converted.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(converted.frameLength)))
            continuation.yield(samples)
        }

        do {
            try engine.start()
            isListening = true

            // Start periodic wake word checking
            checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.checkForWakeWord()
                }
            }

            PushLogger.log("WakeWordListener: Started listening for wake word")
        } catch {
            PushLogger.log("WakeWordListener: Failed to start: \(error)")
        }
    }

    func stopListening() {
        guard isListening else { return }

        checkTimer?.invalidate()
        checkTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isListening = false
        audioBuffer = Data()

        sampleContinuation?.finish()
        sampleContinuation = nil
        drainTask?.cancel()
        drainTask = nil

        PushLogger.log("WakeWordListener: Stopped listening")
    }

    func pauseListening() {
        isPaused = true
        checkTimer?.invalidate()
        checkTimer = nil
        audioBuffer = Data()
        recentAudioLevels = []
        hasSpeechInBuffer = false
        PushLogger.log("WakeWordListener: Paused (recording in progress)")
    }

    func resumeListening() {
        guard isListening, AppState.shared.wakeWordEnabled else { return }

        isPaused = false
        audioBuffer = Data()
        recentAudioLevels = []
        hasSpeechInBuffer = false

        // Add a small delay before resuming to let audio settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, !self.isPaused else { return }
            self.checkTimer = Timer.scheduledTimer(withTimeInterval: self.checkInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.checkForWakeWord()
                }
            }
            PushLogger.log("WakeWordListener: Resumed listening")
        }
    }

    // MARK: - Private

    // nonisolated static: runs on the realtime tap thread, not the main actor.
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
        return error == nil ? outputBuffer : nil
    }

    // Already on the main actor (called from the drain task), so no inner hop.
    private func appendSamples(_ samples: [Float]) {
        guard !isPaused, !samples.isEmpty else { return }

        audioBuffer.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })

        // Track recent audio levels
        recentAudioLevels.append(Self.calculateRMS(samples))
        if recentAudioLevels.count > 15 { // ~0.5 seconds of levels
            recentAudioLevels.removeFirst()
        }

        // Check if any recent audio exceeds speech threshold
        hasSpeechInBuffer = recentAudioLevels.contains { $0 > speechThreshold }

        // Keep only last N seconds of audio
        let maxBytes = Int(sampleRate * bufferDuration) * MemoryLayout<Float>.size
        if audioBuffer.count > maxBytes {
            audioBuffer = audioBuffer.suffix(maxBytes)
        }
    }

    private nonisolated static func calculateRMS(_ samples: [Float]) -> Float {
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count))
    }

    private func checkForWakeWord() async {
        // Guard against concurrent checks, paused state, or active recording
        guard isListening, !isPaused, !isCheckingWakeWord else { return }
        guard !AppState.shared.isListening, !AppState.shared.isProcessing else { return }
        guard audioBuffer.count > 0 else { return }

        // Skip if we recently detected wake word (cooldown period)
        if let lastDetection = lastDetectionTime,
           Date().timeIntervalSince(lastDetection) < detectionCooldown {
            return
        }

        // Skip Whisper if no speech detected in buffer (saves CPU)
        guard hasSpeechInBuffer else { return }

        // Prevent concurrent Whisper calls
        isCheckingWakeWord = true
        defer { isCheckingWakeWord = false }

        let wakeWord = AppState.shared.wakeWord.lowercased()
        let bufferCopy = audioBuffer
        // Use the active engine — WhisperEngine can't serve non-WhisperKit
        // models (Moonshine/Parakeet), and the active engine is already loaded.
        let activeModel = AppState.shared.activeModel

        do {
            let transcription = try await TranscriptionPipeline.transcribe(audioData: bufferCopy, using: activeModel)
            let lowerTranscription = transcription.lowercased()

            // Check if wake word was spoken
            if lowerTranscription.contains(wakeWord) {
                PushLogger.log("WakeWordListener: Wake word detected")

                // Set cooldown and clear buffer
                lastDetectionTime = Date()
                audioBuffer = Data()
                recentAudioLevels = []
                hasSpeechInBuffer = false

                // Trigger callback
                onWakeWordDetected?()
            }
        } catch {
            // Silently ignore transcription errors during wake word detection
        }
    }
}
