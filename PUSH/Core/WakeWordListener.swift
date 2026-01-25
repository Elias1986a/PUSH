import Foundation
import AVFoundation

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
    private let bufferDuration: TimeInterval = 3.0 // Keep last 3 seconds
    private let checkInterval: TimeInterval = 0.75 // Check every 0.75 seconds

    // Callback when wake word detected
    var onWakeWordDetected: (() -> Void)?

    private init() {}

    private func log(_ message: String) {
        let logPath = "/tmp/push_debug.log"
        let timestamp = Date().ISO8601Format()
        let logMessage = "\(timestamp): \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    // MARK: - Public API

    func startListening() {
        guard !isListening else { return }
        guard AppState.shared.wakeWordEnabled else { return }

        log("WakeWordListener: Starting wake word detection for '\(AppState.shared.wakeWord)'")

        audioBuffer = Data()
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
            log("WakeWordListener: Failed to create output format")
            return
        }

        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if let converter = converter {
                if let convertedBuffer = self.convert(buffer: buffer, converter: converter, outputFormat: outputFormat) {
                    self.appendToBuffer(convertedBuffer)
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

            log("WakeWordListener: Started listening for wake word")
        } catch {
            log("WakeWordListener: Failed to start: \(error)")
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

        log("WakeWordListener: Stopped listening")
    }

    func pauseListening() {
        checkTimer?.invalidate()
        checkTimer = nil
        log("WakeWordListener: Paused (recording in progress)")
    }

    func resumeListening() {
        guard isListening, AppState.shared.wakeWordEnabled else { return }

        audioBuffer = Data()
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForWakeWord()
            }
        }
        log("WakeWordListener: Resumed listening")
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

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioBuffer.append(data)

            // Keep only last N seconds of audio
            let maxBytes = Int(self.sampleRate * self.bufferDuration) * MemoryLayout<Float>.size
            if self.audioBuffer.count > maxBytes {
                self.audioBuffer = self.audioBuffer.suffix(maxBytes)
            }
        }
    }

    private func checkForWakeWord() async {
        guard isListening, !AppState.shared.isListening, !AppState.shared.isProcessing else { return }
        guard audioBuffer.count > 0 else { return }

        let wakeWord = AppState.shared.wakeWord.lowercased()
        let bufferCopy = audioBuffer

        do {
            let transcription = try await WhisperEngine.shared.transcribe(audioData: bufferCopy)
            let lowerTranscription = transcription.lowercased()

            // Check if wake word was spoken
            if lowerTranscription.contains(wakeWord) {
                log("WakeWordListener: Wake word '\(wakeWord)' detected in: '\(transcription)'")

                // Clear buffer and trigger recording
                audioBuffer = Data()
                onWakeWordDetected?()
            }
        } catch {
            // Silently ignore transcription errors during wake word detection
        }
    }
}
