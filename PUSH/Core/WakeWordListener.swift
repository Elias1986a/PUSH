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

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if let converter = converter {
                if let convertedBuffer = self.convert(buffer: buffer, converter: converter, outputFormat: outputFormat) {
                    Task { @MainActor in
                        self.appendToBuffer(convertedBuffer)
                    }
                }
            }
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

    private func convert(
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

    private func appendToBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)

        // Calculate RMS for this buffer
        let rms = calculateRMS(channelData[0], frameCount: frameLength)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isPaused else { return }
            self.audioBuffer.append(data)

            // Track recent audio levels
            self.recentAudioLevels.append(rms)
            if self.recentAudioLevels.count > 15 { // ~0.5 seconds of levels
                self.recentAudioLevels.removeFirst()
            }

            // Check if any recent audio exceeds speech threshold
            self.hasSpeechInBuffer = self.recentAudioLevels.contains { $0 > self.speechThreshold }

            // Keep only last N seconds of audio
            let maxBytes = Int(self.sampleRate * self.bufferDuration) * MemoryLayout<Float>.size
            if self.audioBuffer.count > maxBytes {
                self.audioBuffer = self.audioBuffer.suffix(maxBytes)
            }
        }
    }

    private func calculateRMS(_ samples: UnsafePointer<Float>, frameCount: Int) -> Float {
        var sum: Float = 0
        for i in 0..<frameCount {
            sum += samples[i] * samples[i]
        }
        return sqrt(sum / Float(frameCount))
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
