import Foundation
import AVFoundation

/// Captures audio from the microphone into a buffer
class AudioRecorder {
    static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    private var audioData: Data?
    private var isRecording = false

    // Audio format for Whisper: 16kHz, mono, 16-bit PCM
    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1

    private init() {}

    // MARK: - Public API

    func startRecording() {
        guard !isRecording else { return }

        audioData = Data()
        audioEngine = AVAudioEngine()

        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create output format for Whisper (16kHz mono)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            print("AudioRecorder: Failed to create output format")
            return
        }

        // Create converter if sample rates differ
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            if let converter = converter {
                // Convert to 16kHz mono
                let convertedBuffer = self.convert(buffer: buffer, converter: converter, outputFormat: outputFormat)
                self.appendBuffer(convertedBuffer ?? buffer)
            } else {
                self.appendBuffer(buffer)
            }
        }

        do {
            try engine.start()
            isRecording = true
            print("AudioRecorder: Started recording")
        } catch {
            print("AudioRecorder: Failed to start engine: \(error)")
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

        print("AudioRecorder: Stopped recording, captured \(result?.count ?? 0) bytes")
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
            print("AudioRecorder: Conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)

        DispatchQueue.main.async { [weak self] in
            self?.audioData?.append(data)
        }
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
                    // Clamp and convert
                    let clamped = max(-1.0, min(1.0, floats[i]))
                    int16s[i] = Int16(clamped * Float(Int16.max))
                }
            }
        }

        return int16Data
    }

    /// Save audio data to a WAV file (for debugging)
    static func saveToWAV(_ data: Data, sampleRate: Int = 16000) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")

        // WAV header
        var header = Data()
        let dataSize = UInt32(data.count)
        let fileSize = dataSize + 36

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // format (3 = float)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // channels
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) }) // sample rate
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 4).littleEndian) { Array($0) }) // byte rate
        header.append(contentsOf: withUnsafeBytes(of: UInt16(4).littleEndian) { Array($0) }) // block align
        header.append(contentsOf: withUnsafeBytes(of: UInt16(32).littleEndian) { Array($0) }) // bits per sample

        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        var wavData = header
        wavData.append(data)

        do {
            try wavData.write(to: fileURL)
            return fileURL
        } catch {
            print("AudioRecorder: Failed to save WAV: \(error)")
            return nil
        }
    }
}
