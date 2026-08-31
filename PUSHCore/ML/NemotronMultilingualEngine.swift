import Foundation
import FluidAudio

/// Wrapper for FluidAudio's Nemotron 3.5 ASR Streaming Multilingual 0.6B.
///
/// The one non-English engine in PUSH. Every other engine ships an English-only
/// export (the FluidAudio repos are literally named `-en-`), so this is what a
/// user gets when they pick anything other than English from the dictation
/// language picker.
///
/// Cache-aware *streaming*, like `ParakeetStreamingEngine` — choosing a
/// non-English language therefore does not cost the user the streaming
/// behaviour they already have in English.
///
/// **The language is always explicit.** `setLanguage(_:)` selects the encoder's
/// `prompt_id` embedding and `setForcedPrefix(true)` additionally seeds the
/// decoder with that language's `<xx-XX>` tag token — together, as close to
/// "transcribe this as Portuguese" as the model offers. The manager also
/// exposes `detectedLanguage()`; we never call it. Auto-detection is not a
/// feature of this app: the user picked a language, and silently transcribing
/// as something else is worse than transcribing their accent imperfectly.
///
/// Apple Silicon only — the models are int8/ANE exports and FluidAudio throws
/// `unsupportedPlatform` on Intel.
public actor NemotronMultilingualEngine {
    public static let shared = NemotronMultilingualEngine()

    private var manager: StreamingNemotronMultilingualAsrManager?

    /// Which of the two model builds is currently resident ("latin" or
    /// "multilingual"), so a language change can tell a cheap prompt swap from
    /// a genuine model swap.
    private var loadedVariant: String?

    private init() {}

    // MARK: - Model Variants

    /// Chunk size tier to download. 2240 ms is FluidAudio's own default and
    /// highest-throughput tier; the smaller tiers cut latency but emit sparser
    /// punctuation on long sessions (FluidAudio issue #687). The streaming
    /// bake-off may well revisit this — it is the one number here worth tuning.
    private static let chunkMs = 2240

    /// Which of the two published model builds serves a language.
    ///
    /// Deliberately duplicates `StreamingNemotronMultilingualAsrManager
    /// .languageDirectory(for:)` rather than calling it, for one difference:
    /// FluidAudio routes `"auto"` to the full-vocab `multilingual` build so
    /// that auto-detection can reach every language. We never want detection,
    /// so an `"auto"` that somehow reaches this engine lands on English's
    /// build instead — the smaller, faster one, and the sane default for this
    /// app's users. Everything else matches FluidAudio exactly; getting the
    /// mapping wrong downloads the wrong ~600 MB.
    public nonisolated static func vocabVariant(for languageCode: String) -> String {
        let code = languageCode.lowercased()
        if code == "auto" { return "latin" }
        let latinPrefixes = ["en", "es", "fr", "it", "pt", "de"]
        return latinPrefixes.contains(where: { code.hasPrefix($0) }) ? "latin" : "multilingual"
    }

    // MARK: - Model Storage

    /// Root of FluidAudio's on-disk cache for this repo.
    ///
    /// Derived from `Repo.folderName` rather than hardcoded, for the same
    /// reason as `ParakeetUnifiedEngine`: the local folder is not the
    /// HuggingFace repo name, and hardcoding it once already produced a false
    /// "Not downloaded" in Settings while the model was loaded and serving.
    private nonisolated static var repoDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
    }

    /// Mirrors the layout `downloadVariant(languageCode:chunkMs:to:)` writes:
    /// `…/Models/<repo>/<latin|multilingual>/<chunkMs>ms/`.
    private nonisolated static func variantDirectory(_ variant: String) -> URL {
        repoDirectory
            .appendingPathComponent(variant, isDirectory: true)
            .appendingPathComponent("\(chunkMs)ms", isDirectory: true)
    }

    /// Where a given language's models land on disk.
    public nonisolated static func modelDirectory(for languageCode: String) -> URL {
        variantDirectory(vocabVariant(for: languageCode))
    }

    /// Everything this engine owns on disk, both builds.
    ///
    /// The per-language directory above is the wrong answer for Settings, which
    /// asks one question about one engine: a user who has dictated in Japanese
    /// and Spanish has two builds down, and reporting only the current
    /// language's would under-count the storage and offer to delete half of it.
    public nonisolated static var modelDirectory: URL { repoDirectory }

    /// True when *either* build is on disk.
    ///
    /// The Settings row asks one yes/no question about one engine, so
    /// "downloaded" has to mean "at least one language is ready to run" — a
    /// per-language answer would need a per-language row.
    public nonisolated static func isModelDownloaded() -> Bool {
        ["latin", "multilingual"].contains { variant in
            let contents = (try? FileManager.default.contentsOfDirectory(
                atPath: variantDirectory(variant).path)) ?? []
            return contents.contains { $0.hasSuffix(".mlmodelc") }
        }
    }

    /// Removes both builds — deleting one language's models while leaving the
    /// other behind would leave Settings reporting "downloaded" for an engine
    /// the user just deleted.
    public nonisolated static func deleteModel() throws {
        let dir = repoDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
            PushLogger.log("NemotronMultilingualEngine: Models deleted from \(dir.path)")
        }
    }

    // MARK: - Languages

    /// The languages this model can actually transcribe, read from the loaded
    /// model's own `prompt_dictionary`.
    ///
    /// Returns `[]` when nothing is loaded, deliberately: there is no hardcoded
    /// fallback list. A constant that disagrees with the model would offer the
    /// user a language the encoder has no prompt embedding for, and they would
    /// discover it only by dictating into it. An empty picker is a bug the user
    /// can report; a wrong picker is one they cannot.
    ///
    /// `"auto"` is filtered out — it is a real key in the dictionary, and it is
    /// the one option this app never offers.
    public func supportedLanguages() async -> [DictationLanguage] {
        guard let manager else { return [] }
        let codes = await manager.config.promptDictionary.keys
        return codes
            .filter { $0.lowercased() != "auto" }
            .map { DictationLanguage(code: $0) }
            .sorted()
    }

    // MARK: - Lifecycle

    /// Loads (downloading on first use) the build serving `languageCode` and
    /// pins the model to that language.
    ///
    /// Switching between two languages in the same build — Portuguese to
    /// Spanish, say — is only a prompt id and a decoder reseed, so the resident
    /// models are kept and the ~600 MB download and multi-second load are
    /// skipped. Crossing builds (Spanish to Japanese) is a genuine model swap
    /// and has to tear down first.
    public func loadModel(languageCode: String) async throws {
        let variant = Self.vocabVariant(for: languageCode)

        if let manager, loadedVariant == variant {
            await manager.setLanguage(languageCode)
            await manager.setForcedPrefix(true)
            PushLogger.log("NemotronMultilingualEngine: Switched to \(languageCode) within the \(variant) build")
            return
        }

        if manager != nil {
            unloadModel()
        }

        PushLogger.log("NemotronMultilingualEngine: Loading \(variant) build (\(Self.chunkMs)ms) for \(languageCode)...")

        do {
            // No `to:` — FluidAudio picks its own cache root, and
            // `variantDirectory(_:)` above mirrors that path rather than
            // dictating it, so the download and the on-disk check cannot drift.
            let shared = try await StreamingNemotronMultilingualAsrManager.downloadAndPreloadShared(
                languageCode: languageCode,
                chunkMs: Self.chunkMs
            )

            let manager = StreamingNemotronMultilingualAsrManager()
            try await manager.loadFromShared(shared)

            // Order matters: the forced prefix is seeded from the language set
            // just above, so language first, then prefix.
            await manager.setLanguage(languageCode)
            await manager.setForcedPrefix(true)

            self.manager = manager
            self.loadedVariant = variant
            PushLogger.log("NemotronMultilingualEngine: ✅ \(variant) build loaded for \(languageCode)")
        } catch {
            PushLogger.log("NemotronMultilingualEngine: ❌ Failed to load model: \(error)")
            throw ParakeetEngineError.loadFailed(error.localizedDescription)
        }
    }

    public func unloadModel() {
        manager = nil
        loadedVariant = nil
        PushLogger.log("NemotronMultilingualEngine: Model unloaded")
    }

    /// Loads the model and runs a second of silence through it so the first
    /// real utterance does not pay CoreML's cold-start cost.
    public func warmup(languageCode: String) async {
        PushLogger.log("NemotronMultilingualEngine: Starting warmup for \(languageCode)...")
        let startTime = Date()

        do {
            try await loadModel(languageCode: languageCode)

            let silentAudio = [Float](repeating: 0.0, count: 16000)
            _ = try await transcribeFloats(silentAudio)

            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log("NemotronMultilingualEngine: ✅ Warmup complete in \(String(format: "%.2f", elapsed))s")
        } catch {
            PushLogger.log("NemotronMultilingualEngine: Warmup failed: \(error)")
        }
    }

    // MARK: - Transcription

    /// Transcribes one utterance of 16 kHz mono float samples.
    ///
    /// Resets first: `finish()` clears the accumulated tokens but not the
    /// encoder's cache-aware state, so without this each utterance would decode
    /// with the tail of the previous one still in context. `reset()` also
    /// re-seeds the forced language prefix, which is exactly what a new
    /// utterance wants.
    /// Batch entry point: one utterance of 16 kHz mono Float32, as `Data`.
    ///
    /// This is what `TranscriptionPipeline` routes to. The engine streams during
    /// recording when it is driven live, but the pipeline's contract is a whole
    /// buffer after release, and it has to be honoured — a wake-word trigger and
    /// the comparison tool both arrive here with audio that was never fed in.
    ///
    /// No implicit load: unlike the Parakeet engines, loading needs a language
    /// this call doesn't carry, and guessing one would download the wrong 600 MB.
    /// `ModelLoader` has already loaded the right build by the time audio lands.
    public func transcribe(audioData: Data) async throws -> String {
        let samples = Self.floatArray(from: audioData)
        guard !samples.isEmpty else { throw ParakeetEngineError.emptyAudio }
        return try await transcribeFloats(samples)
    }

    /// 16 kHz mono Float32, as `AudioRecorder` hands it to every engine.
    private nonisolated static func floatArray(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        var samples = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            for i in 0..<count { samples[i] = floats[i] }
        }
        return samples
    }

    public func transcribeFloats(_ samples: [Float]) async throws -> String {
        guard let manager else {
            throw ParakeetEngineError.notInitialized
        }
        guard !samples.isEmpty else {
            throw ParakeetEngineError.emptyAudio
        }

        let start = Date()
        await manager.reset()
        _ = try await manager.process(samples: samples)
        let text = try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = Date().timeIntervalSince(start)

        // Duration + inference time only — never the transcript, and never the
        // language alongside it.
        PushLogger.log(String(
            format: "NemotronMultilingualEngine: Transcribed %.2fs audio in %.3fs (%d chars)",
            Double(samples.count) / 16000.0, elapsed, text.count))
        return text
    }
}
