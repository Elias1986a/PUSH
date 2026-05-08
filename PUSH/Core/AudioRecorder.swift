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

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if let converter = converter {
                let convertedBuffer = self.convert(buffer: buffer, converter: converter, outputFormat: outputFormat)
                Task { @MainActor in
                    self.appendBuffer(convertedBuffer ?? buffer)
                }
            } else {
                Task { @MainActor in
                    self.appendBuffer(buffer)
                }
            }
        }

        do {
            try engine.start()
            isRecording = true

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
        }
    }

    func stopRecording() -> Data? {
        guard isRecording else { return nil }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

        let result = audioData
        audioData = nil

        PushLogger.log("AudioRecorder: Stopped recording, captured \(result?.count ?? 0) bytes")
        return result
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

        if let error = error {
            PushLogger.log("AudioRecorder: Conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)

        let floats = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        Task { await sileroVAD.processSamples(floats) }

        audioData?.append(data)
    }
}

// MARK: - Audio Data Conversion Helpers

extension AudioRecorder {
    /// Convert Float32 audio data to Int16 for Whisper
    static func convertToInt16(_ floatData: Data) -> Data {
        let floatCount = floatData.count / MemoryLayout<Float>.size
        var int16Data = Data(count: floatCount * MemoryLayout<Int16>.size)

        floatData.withUnsafeBytes { floatBuffer in
            int16Data.withUnsafeMutableBytes { int16Buffer in
                let floats = floatBuffer.bindMemory(to: Float.self)
                let int16s = int16Buffer.bindMemory(to: Int16.self)

                for i in 0..<floatCount {
                    let clamped = max(-1.0, min(1.0, floats[i]))
                    int16s[i] = Int16(clamped * Float(Int16.max))
                }
            }
        }

        return int16Data
    }

    /// Save audio data to a WAV file (for debugging)
    static func saveToWAV(_ data: Data, sampleRate: Int = 16000) -> URL? {
#if DEBUG
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")

        var header = Data()
        let dataSize = UInt32(data.count)
        let fileSize = dataSize + 36

        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)

        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 4).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(4).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(32).littleEndian) { Array($0) })

        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        var wavData = header
        wavData.append(data)

        do {
            try wavData.write(to: fileURL)
            return fileURL
        } catch {
            PushLogger.log("AudioRecorder: Failed to save WAV: \(error)")
            return nil
        }
#else
        return nil
#endif
    }
}
