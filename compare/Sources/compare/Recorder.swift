import AVFoundation
import Foundation

/// Microphone capture producing exactly what PUSH's engines are fed: 16 kHz mono
/// Float32 PCM.
///
/// Deliberately not reusing `AudioRecorder` from the app. That file carries volume
/// ducking, VAD wiring and app state this tool has no use for, and importing it would
/// drag the whole app target along behind it.
@MainActor
final class Recorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples = Data()
    private(set) var isRecording = false

    /// The format the engines expect.
    private static let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    /// Ask for the microphone explicitly.
    ///
    /// Letting `AVAudioEngine.start()` trigger the prompt as a side effect is
    /// unreliable: when access is refused it tends to hand back a zero-channel input
    /// rather than an error, which reads as "no audio device" and hides the real cause.
    /// Asking outright means a denial is a denial, and can be reported as one.
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func start() throws {
        guard !isRecording else { return }
        samples.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw RecorderError.noInput }
        converter = AVAudioConverter(from: inputFormat, to: Self.target)

        // The tap's buffer is recycled the instant the callback returns, so everything
        // that outlives the callback is copied out of it here.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let converted = Self.convert(buffer, using: self.converter, to: Self.target)
            guard let converted, let channel = converted.floatChannelData?[0] else { return }
            let chunk = Data(bytes: channel, count: Int(converted.frameLength) * MemoryLayout<Float>.size)
            Task { @MainActor in self.samples.append(chunk) }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stop and hand back everything captured.
    func stop() -> Data {
        guard isRecording else { return Data() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return samples
    }

    var seconds: Double {
        Double(samples.count / MemoryLayout<Float>.size) / Self.target.sampleRate
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter?,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : out
    }
}

enum RecorderError: LocalizedError {
    case noInput
    var errorDescription: String? { "No audio input device" }
}
