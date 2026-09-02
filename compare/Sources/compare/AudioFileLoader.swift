import AVFoundation
import Foundation

/// Loads an audio file as the same 16 kHz mono float `Data` the `Recorder`
/// produces, so a file and a live recording are interchangeable inputs to
/// `EngineComparison.run`.
///
/// This is what makes the benchmark tiers possible: `say`-synthesised smoke
/// clips and a WER corpus with ground-truth transcripts are files, and every
/// language has to be checkable without anyone reading a script aloud.
///
/// Deliberately not "play the file through the speakers and re-record it":
/// that adds room acoustics a close-talk dictation mic never sees, and
/// degrades engines unevenly, which would make the benchmark measure the room.
enum AudioFileLoader {

    /// The rate the engines are fed at — the same constant `Recorder` targets.
    static let sampleRate: Double = 16000

    /// Byte-for-byte the format `Recorder.stop()` hands back: 16 kHz, mono,
    /// Float32, non-interleaved, with the samples of channel 0 laid out raw.
    private static let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    /// How many seconds of audio a `Recorder`-shaped buffer holds.
    static func seconds(of audio: Data) -> Double {
        Double(audio.count / MemoryLayout<Float>.size) / sampleRate
    }

    /// Decode `url` to 16 kHz mono float samples.
    ///
    /// Errors are thrown rather than returned as empty `Data` on purpose: a file
    /// that failed to decode and a file of silence must not look alike, the same
    /// principle `EngineComparison.measure` follows for engine failures.
    static func load(_ url: URL) throws -> Data {
        let name = url.lastPathComponent

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioFileError.unreadable(name, Self.reason(for: error, at: url))
        }

        // `processingFormat` is always deinterleaved Float32, whatever the file's
        // own encoding is — so the only differences left to handle are the sample
        // rate and the channel count.
        let source = file.processingFormat
        guard file.length > 0, source.sampleRate > 0, source.channelCount > 0 else {
            throw AudioFileError.empty(name)
        }

        guard let monoSource = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: source.sampleRate,
            channels: 1, interleaved: false)
        else { throw AudioFileError.unsupported(name, source) }

        // Downmixing by hand and leaving the converter a mono-to-mono resample:
        // a converter asked to change rate and channel count at once picks its own
        // channel map, and a silently dropped channel would read as a bad engine
        // rather than a bad load. Averaging is explicit and checkable.
        var converter: AVAudioConverter?
        if source.sampleRate != sampleRate {
            guard let resampler = AVAudioConverter(from: monoSource, to: target) else {
                throw AudioFileError.unsupported(name, source)
            }
            converter = resampler
        }

        // Read in chunks: a corpus clip is short, but nothing here should depend on
        // that, and one buffer per file would size an allocation off the file.
        let chunk: AVAudioFrameCount = 16384
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunk) else {
            throw AudioFileError.unsupported(name, source)
        }

        var samples = Data()
        // Bounded by the file's own frame count rather than by reading until it
        // complains: `read` reports the end of a file by throwing `eofErr`, which is
        // indistinguishable from a real read failure once it has been localized.
        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(min(Int64(chunk), file.length - file.framePosition))
            do {
                try file.read(into: readBuffer, frameCount: remaining)
            } catch let error as NSError where error.code == eofErr {
                // A compressed file's `length` is an estimate and can overshoot by a
                // packet; that is the end of the audio, not a failure.
                break
            } catch {
                throw AudioFileError.unreadable(name, Self.reason(for: error, at: url))
            }
            guard readBuffer.frameLength > 0 else { break }

            guard let mono = downmix(readBuffer, to: monoSource) else {
                throw AudioFileError.unsupported(name, source)
            }
            if let converter {
                guard let resampled = resample(mono, using: converter) else {
                    throw AudioFileError.conversionFailed(name, source)
                }
                samples.append(bytes(of: resampled))
            } else {
                samples.append(bytes(of: mono))
            }
        }

        // Flush whatever the resampler is still holding, so the last few
        // milliseconds of a clip are not quietly clipped off the end.
        if let converter, let tail = drain(converter) {
            samples.append(bytes(of: tail))
        }

        guard !samples.isEmpty else { throw AudioFileError.empty(name) }
        return samples
    }

    /// Average every channel into one. A stereo file recorded from one mic has the
    /// speech in both channels; taking only the left would throw half of it away.
    private static func downmix(
        _ buffer: AVAudioPCMBuffer, to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard let input = buffer.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let output = out.floatChannelData?[0]
        else { return nil }

        if channels == 1 {
            output.update(from: input[0], count: frames)
        } else {
            let scale = 1 / Float(channels)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += input[channel][frame] }
                output[frame] = sum * scale
            }
        }
        out.frameLength = buffer.frameLength
        return out
    }

    /// One chunk through the resampler. The converter keeps its own state between
    /// calls, so successive chunks join up without a seam.
    private static func resample(
        _ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let ratio = sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

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

    /// Whatever the resampler still holds after the last chunk.
    private static func drain(_ converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else { return nil }
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { _, outStatus in
            outStatus.pointee = .endOfStream
            return nil
        }
        return out.frameLength > 0 ? out : nil
    }

    /// Turn CoreAudio's four-character status codes into something readable.
    /// `NSError`'s own text for these is "The operation couldn't be completed.
    /// (com.apple.coreaudio.avfaudio error 2003334207.)", which tells nobody
    /// whether the file is missing, not audio, or genuinely broken.
    private static func reason(for error: Error, at url: URL) -> String {
        let notAudio = "macOS can't decode it as audio"
        switch (error as NSError).code {
        case 1954115647, 1718449215, 1685348671:  // 'typ?', 'fmt?', 'dta?'
            return notAudio
        case 2003334207:  // 'wht?' — missing, or a path that isn't a file at all
            return FileManager.default.fileExists(atPath: url.path) ? notAudio : "no such file"
        default:
            return error.localizedDescription
        }
    }

    private static func bytes(of buffer: AVAudioPCMBuffer) -> Data {
        guard let channel = buffer.floatChannelData?[0] else { return Data() }
        return Data(bytes: channel, count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    }
}

enum AudioFileError: LocalizedError {
    case unreadable(String, String)
    case empty(String)
    case unsupported(String, AVAudioFormat)
    case conversionFailed(String, AVAudioFormat)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name, let reason):
            return "Couldn't read \(name) — \(reason)"
        case .empty(let name):
            return "\(name) contains no audio"
        case .unsupported(let name, let format):
            return "Can't convert \(name) from \(Self.describe(format)) to 16 kHz mono"
        case .conversionFailed(let name, let format):
            return "Conversion of \(name) from \(Self.describe(format)) to 16 kHz mono failed"
        }
    }

    /// Named, not dumped: `AVAudioFormat`'s own description is a page of CoreAudio
    /// struct fields, and the two numbers that matter here are the rate and channels.
    private static func describe(_ format: AVAudioFormat) -> String {
        let rate = format.sampleRate / 1000
        let channels = format.channelCount == 1 ? "mono" : "\(format.channelCount) channels"
        return "\(rate.formatted(.number.precision(.fractionLength(0...1)))) kHz \(channels)"
    }
}
