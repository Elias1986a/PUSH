import XCTest
import AVFoundation
@testable import PUSH
@testable import PUSHCore

/// Exercises the Apple Speech path without a microphone, using synthesized speech.
final class AppleSpeechSmokeTest: XCTestCase {

    /// Synthesize a clip with `say` rather than shipping a fixture or asking anyone to
    /// read one aloud. Returns nil if synthesis isn't possible, and the test skips.
    private static func synthesizeClip() -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let aiff = dir.appendingPathComponent("push-apple-speech-test.aiff")
        let wav = dir.appendingPathComponent("push-apple-speech-test.wav")
        if FileManager.default.fileExists(atPath: wav.path) { return wav }

        func run(_ launchPath: String, _ args: [String]) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }

        guard run("/usr/bin/say", ["-o", aiff.path, Self.spokenText]),
              run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEF32@16000", "-c", "1", aiff.path, wav.path])
        else { return nil }
        return wav
    }

    private static let spokenText =
        "The quick brown fox jumps over the lazy dog. We need about four point eight million users."

    /// Load a WAV as the 16 kHz mono Float32 `Data` the engines are handed.
    private func clipData(at url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                      frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)

        let converter = AVAudioConverter(from: file.processingFormat, to: format)!
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length) * 2)!
        var done = false
        var err: NSError?
        _ = converter.convert(to: out, error: &err) { _, status in
            if done { status.pointee = .endOfStream; return nil }
            done = true
            status.pointee = .haveData
            return buffer
        }
        if let err { throw err }
        let channel = out.floatChannelData![0]
        return Data(bytes: channel, count: Int(out.frameLength) * MemoryLayout<Float>.size)
    }

    func testTranscribesRealSpeech() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("needs macOS 26") }
        guard AppleSpeechEngine.isSupported else { throw XCTSkip("transcriber unavailable") }
        guard let clip = Self.synthesizeClip() else {
            throw XCTSkip("could not synthesize a clip with `say`")
        }

        let audio = try clipData(at: clip)
        print("SMOKE| clip = \(Double(audio.count / 4) / 16000.0)s")

        try await AppleSpeechEngine.shared.loadModel()
        let t = Date()
        let raw = try await AppleSpeechEngine.shared.transcribe(audioData: audio)
        print("SMOKE| raw   -> \(raw)")
        print("SMOKE| took  -> \(String(format: "%.2f", Date().timeIntervalSince(t)))s")

        let final = TranscriptionPipeline.postProcess(raw, hasNativePunctuation: true)
        print("SMOKE| final -> \(final)")

        XCTAssertFalse(raw.isEmpty, "Apple Speech returned nothing for real speech")
        XCTAssertTrue(raw.lowercased().contains("fox"), "expected the clip's words")
    }
}
