import AVFoundation
import Foundation
import Speech

/// Apple's on-device `SpeechAnalyzer` / `SpeechTranscriber` (macOS 26).
///
/// Unlike every other engine here, there are no weights to fetch or store: the OS owns
/// the assets. So `loadModel()` installs and reserves a *locale* rather than downloading
/// a model, and download state is a question for the system rather than for disk.
///
/// A `SpeechAnalyzer` cannot be restarted once finalized, so one is built per utterance.
/// `.processLifetime` retention is what keeps that cheap — it tells the OS to hold the
/// loaded model between utterances instead of paging it back in on every press.
@available(macOS 26, *)
public actor AppleSpeechEngine {
    public static let shared = AppleSpeechEngine()

    /// The locale whose assets are installed and reserved. `nil` until `loadModel()` succeeds.
    private var readyLocale: Locale?

    /// PUSH hands every engine 16 kHz mono Float32 (see `AudioRecorder`).
    private static let inputSampleRate: Double = 16000

    private init() {}

    // MARK: - Availability

    /// Whether this Mac can run the transcriber at all. Cheap and synchronous, so the
    /// settings picker can filter the model out without an await.
    public nonisolated static var isSupported: Bool {
        SpeechTranscriber.isAvailable
    }

    /// Asset state for the locale we'd use. The settings row shows this instead of a
    /// download button — the OS manages these assets, and a progress bar we don't
    /// control would be a fiction.
    public static func installStatus() async -> AssetInventory.Status {
        guard let locale = await resolveLocale() else { return .unsupported }
        return await AssetInventory.status(forModules: [SpeechTranscriber(locale: locale, preset: .transcription)])
    }

    /// The user's own locale when the transcriber supports it, else en-US. Returns nil
    /// when neither is supported, which is the one case the caller must surface.
    private static func resolveLocale() async -> Locale? {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
            return match
        }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }

    // MARK: - Public API

    /// Ensure the locale's assets are installed and reserved.
    ///
    /// First run for a locale genuinely downloads from Apple and can take a while — this
    /// is the equivalent of another engine's model fetch, and the caller should expect it
    /// to be slow exactly once.
    public func loadModel() async throws {
        if readyLocale != nil { return }

        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechEngineError.unsupportedSystem
        }
        guard let locale = await Self.resolveLocale() else {
            throw AppleSpeechEngineError.unsupportedLocale(Locale.current.identifier)
        }

        PushLogger.log("AppleSpeechEngine: Preparing \(locale.identifier)...")

        let probe = SpeechTranscriber(locale: locale, preset: .transcription)
        if await AssetInventory.status(forModules: [probe]) != .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                PushLogger.log("AppleSpeechEngine: Installing system assets for \(locale.identifier)...")
                try await request.downloadAndInstall()
            }
        }

        // Reserving tells the OS to keep this locale's assets around for us. The system
        // caps how many locales may be reserved at once, so a failure here is not fatal —
        // transcription still works, it just may need to re-fetch later.
        do {
            try await AssetInventory.reserve(locale: locale)
        } catch {
            PushLogger.log("AppleSpeechEngine: Could not reserve \(locale.identifier): \(error.localizedDescription)")
        }

        readyLocale = locale
        PushLogger.log("AppleSpeechEngine: ✅ Ready (\(locale.identifier))")
    }

    public func unloadModel() async {
        if let locale = readyLocale {
            _ = await AssetInventory.release(reservedLocale: locale)
        }
        readyLocale = nil
        PushLogger.log("AppleSpeechEngine: Unloaded")
    }

    /// Warm up by running one silent second through the whole path.
    ///
    /// This is what pays for `.processLifetime` retention: it forces the first (slow)
    /// model load to happen here rather than on the user's first press.
    public func warmup() async {
        PushLogger.log("AppleSpeechEngine: Starting warmup...")
        let startTime = Date()

        do {
            try await loadModel()
            let silence = Data(count: Int(Self.inputSampleRate) * MemoryLayout<Float>.size)
            _ = try await transcribe(audioData: silence)

            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("AppleSpeechEngine: ✅ Warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("AppleSpeechEngine: Warmup failed: \(error)")
        }
    }

    /// Transcribe 16 kHz mono Float32 PCM.
    public func transcribe(audioData: Data) async throws -> String {
        if readyLocale == nil {
            PushLogger.log("AppleSpeechEngine: Not loaded, loading...")
            try await loadModel()
        }
        guard let locale = readyLocale else {
            throw AppleSpeechEngineError.notInitialized
        }
        guard !audioData.isEmpty else {
            throw AppleSpeechEngineError.emptyAudio
        }

        let start = Date()

        // Batch, not progressive: PUSH transcribes after the key is released, so volatile
        // partial results would be extra work nobody reads.
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechEngineError.noCompatibleAudioFormat
        }
        let buffer = try Self.makeBuffer(from: audioData, in: analyzerFormat)

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime)
        )

        // Drain before finalizing. The transcriber can emit its last result *during*
        // finalizeAndFinishThroughEndOfInput(), so the consumer has to already be running
        // or that result is lost and the utterance comes back empty.
        let collector = Task {
            var parts: [String] = []
            for try await result in transcriber.results {
                parts.append(String(result.text.characters))
            }
            return parts.joined()
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = Date().timeIntervalSince(start)

        // Same shape as the other engines so an A/B reads directly. Duration and counts
        // only — never transcript text.
        PushLogger.log(String(
            format: "AppleSpeechEngine: Transcribed %.2fs audio in %.3fs (%d chars)",
            Double(audioData.count / MemoryLayout<Float>.size) / Self.inputSampleRate,
            elapsed, text.count))
        return text
    }

    // MARK: - Private

    /// Wrap our 16 kHz Float32 bytes in a buffer the analyzer accepts, converting when
    /// its preferred format differs (it usually does — sample rate and interleaving are
    /// both the system's choice, not ours).
    private static func makeBuffer(from data: Data, in analyzerFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AppleSpeechEngineError.noCompatibleAudioFormat
        }

        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Float>.size)
        guard frameCount > 0,
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)
        else {
            throw AppleSpeechEngineError.emptyAudio
        }
        source.frameLength = frameCount
        data.withUnsafeBytes { raw in
            if let base = raw.bindMemory(to: Float.self).baseAddress,
               let dest = source.floatChannelData?[0] {
                dest.update(from: base, count: Int(frameCount))
            }
        }

        if sourceFormat == analyzerFormat { return source }

        guard let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat) else {
            throw AppleSpeechEngineError.noCompatibleAudioFormat
        }
        let ratio = analyzerFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else {
            throw AppleSpeechEngineError.noCompatibleAudioFormat
        }

        // One-shot: hand over the whole buffer, then report end-of-stream. Returning the
        // same buffer twice would make the converter loop forever.
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return source
        }

        if status == .error {
            throw AppleSpeechEngineError.conversionFailed(
                conversionError?.localizedDescription ?? "unknown")
        }
        return output
    }
}

// MARK: - Errors

@available(macOS 26, *)
public enum AppleSpeechEngineError: LocalizedError {
    case unsupportedSystem
    case unsupportedLocale(String)
    case notInitialized
    case emptyAudio
    case noCompatibleAudioFormat
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "Apple Speech isn't available on this Mac"
        case .unsupportedLocale(let id):
            return "Apple Speech doesn't support \(id) or English"
        case .notInitialized:
            return "Apple Speech engine not initialized"
        case .emptyAudio:
            return "No audio data to transcribe"
        case .noCompatibleAudioFormat:
            return "No audio format compatible with Apple Speech"
        case .conversionFailed(let reason):
            return "Failed to convert audio for Apple Speech: \(reason)"
        }
    }
}
