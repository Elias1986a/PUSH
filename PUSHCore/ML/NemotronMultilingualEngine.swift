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
/// **The language is always explicit**, and `setLanguage(_:)` — which selects
/// the encoder's `prompt_id` embedding — is the whole of how we say so. This is
/// a `…ModelWithPrompt` model: the prompt id *is* its language control, and it
/// is a hard one. Fed audio in a language the prompt id does not name, the model
/// emits nothing at all rather than guessing, which is precisely the behaviour
/// this app wants. The manager also exposes `detectedLanguage()`; we never call
/// it. Auto-detection is not a feature of this app: the user picked a language,
/// and silently transcribing as something else is worse than transcribing their
/// accent imperfectly.
///
/// FluidAudio additionally offers `setForcedPrefix(true)`, a Whisper-style
/// second lock that seeds the decoder with the language's `<xx-XX>` tag token.
/// **We deliberately leave it off** — see `setForcedPrefix(false)` in
/// `loadModel` for the measurements. It is not a second opinion on the same
/// question; it corrupts the first word of every utterance.
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

    /// Bumped by every `loadModel` call. Actors are reentrant, so this is how a
    /// load that has been overtaken finds out before it commits — see the
    /// comment in `loadModel`.
    private var loadGeneration = 0

    /// Internal rather than private purely so tests can build a known-unloaded
    /// instance. The app has exactly one engine and must go through `shared`;
    /// a second instance would mean a second ~600 MB model resident.
    init() {}

    // MARK: - Model Variants

    /// Chunk size tier to download. 2240 ms is FluidAudio's own default and
    /// highest-throughput tier; the smaller tiers cut latency but emit sparser
    /// punctuation on long sessions (FluidAudio issue #687). The streaming
    /// bake-off may well revisit this — it is the one number here worth tuning.
    private static let chunkMs = 2240

    /// The language this engine will actually load for.
    ///
    /// The app never asks for `"auto"` — the user always picks a language — but
    /// a stored preference or the comparison tool can still hand us one, so it
    /// gets resolved rather than trusted. Resolving it *here*, once, before
    /// anything downstream sees it, is what keeps our own bookkeeping and
    /// FluidAudio's download path pointed at the same build: see the divergence
    /// described on `vocabVariant(for:)`.
    ///
    /// English is the landing spot rather than the full-vocab build because the
    /// alternative — letting the model pick — is auto-detection by the back
    /// door, and this app does not do that.
    nonisolated static func effectiveLanguageCode(_ languageCode: String) -> String {
        languageCode.lowercased() == "auto" ? "en-US" : languageCode
    }

    /// Which of the two published model builds serves a language.
    ///
    /// Deliberately duplicates `StreamingNemotronMultilingualAsrManager
    /// .languageDirectory(for:)` rather than calling it, for one difference:
    /// FluidAudio routes `"auto"` to the full-vocab `multilingual` build so
    /// that auto-detection can reach every language. We never want detection,
    /// so `"auto"` maps to English's build here — the smaller, faster one.
    ///
    /// That divergence is only safe because no raw `"auto"` ever reaches
    /// FluidAudio: every path through this file resolves it with
    /// `effectiveLanguageCode(_:)` first, so the build we record and the build
    /// FluidAudio downloads are always the same one. Forwarding the raw string
    /// instead loads `multilingual` while recording `latin`, which then makes
    /// every later latin language take the cheap-switch path onto the wrong,
    /// slower build with no way back.
    ///
    /// Everything other than `"auto"` matches FluidAudio exactly, and
    /// `testVocabVariantMatchesFluidAudioExceptForAuto` holds us to that on
    /// every dependency bump — getting the mapping wrong downloads the wrong
    /// ~600 MB.
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
        variantDirectory(vocabVariant(for: effectiveLanguageCode(languageCode)))
    }

    /// Whether one build is on disk, i.e. whether it can load without a download.
    private nonisolated static func hasBuild(_ variant: String) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(
            atPath: variantDirectory(variant).path)) ?? []
        return contents.contains { $0.hasSuffix(".mlmodelc") }
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
        ["latin", "multilingual"].contains(where: hasBuild)
    }

    /// True when the build serving `languageCode` specifically is on disk.
    ///
    /// The either-variant answer above is right for the Settings row, but it
    /// will happily say "Downloaded" immediately before a surprise second
    /// ~600 MB pull: a user who downloaded Japanese and then picks Spanish
    /// crosses vocab groups, and on a slow connection that reads as an
    /// unexplained multi-minute stall while the UI insists the model is already
    /// there. Anything about to switch language should ask this one and warn.
    ///
    /// Built on the same two helpers as the row above so the two cannot drift.
    public nonisolated static func isModelDownloaded(for languageCode: String) -> Bool {
        hasBuild(vocabVariant(for: effectiveLanguageCode(languageCode)))
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
    /// The dictionary is a lookup table, not a menu: it holds 121 keys for 84
    /// prompts, and the spare 37 are aliases, misspellings and invented
    /// regions. `NemotronPromptDictionary.offeredLanguages(in:)` reduces it to
    /// the menu; see there for what is dropped and why.
    public func supportedLanguages() async -> [DictationLanguage] {
        guard let manager else { return [] }
        return NemotronPromptDictionary.offeredLanguages(in: await manager.config.promptDictionary)
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
        // Resolve once, forward the resolved value everywhere below. Passing the
        // caller's raw string to FluidAudio while deriving `variant` from our own
        // mapping is how the two end up describing different builds.
        let code = Self.effectiveLanguageCode(languageCode)
        let variant = Self.vocabVariant(for: code)

        // Claim this request before the first suspension point. A second
        // loadModel can start while this one is parked on a ~600 MB download,
        // and with no token the *slower* call commits its manager last, leaving
        // the engine transcribing in a language nobody asked for — the exact
        // silent failure this file's header says it refuses.
        //
        // Chosen over a stored `Task` that later callers await: coalescing only
        // helps identical requests, whereas the dangerous case here is two
        // *different* languages, and a serial chain would make the second
        // language sit out the first language's entire download before starting.
        loadGeneration &+= 1
        let generation = loadGeneration

        if let manager, loadedVariant == variant {
            await manager.setLanguage(code)
            guard generation == loadGeneration else { return }
            await manager.setForcedPrefix(false)
            PushLogger.log("NemotronMultilingualEngine: Switched to \(code) within the \(variant) build")
            return
        }

        if manager != nil {
            // Torn down inline rather than through `unloadModel()`, which bumps
            // the generation to cancel in-flight loads — and would therefore
            // cancel this one.
            manager = nil
            loadedVariant = nil
        }

        PushLogger.log("NemotronMultilingualEngine: Loading \(variant) build (\(Self.chunkMs)ms) for \(code)...")

        do {
            // No `to:` — FluidAudio picks its own cache root, and
            // `variantDirectory(_:)` above mirrors that path rather than
            // dictating it, so the download and the on-disk check cannot drift.
            let shared = try await StreamingNemotronMultilingualAsrManager.downloadAndPreloadShared(
                languageCode: code,
                chunkMs: Self.chunkMs
            )

            let manager = StreamingNemotronMultilingualAsrManager()
            try await manager.loadFromShared(shared)

            await manager.setLanguage(code)

            // Off, and said out loud rather than left to FluidAudio's default,
            // because the default is the only thing standing between us and a
            // bug that reads as "the model is bad at Portuguese".
            //
            // `setForcedPrefix(true)` runs the decoder once on the `<pt-BR>` tag
            // token and keeps the resulting LSTM state as the utterance's
            // starting point. On a Whisper-style decoder that is a language
            // lock. On this model it is an off-distribution prediction-network
            // state, and the tokens it emits first are garbage: over eight
            // `say -v Luciana` pt-BR phrases the utterance's own first word
            // survived 0/8 times with the prefix on — usually replaced by a
            // spurious "a" or "a gente" — against 8/8 with it off. No amount of
            // lead-in silence rescues it; only turning it off does.
            //
            // Nor is it a useful second lock. `prompt_id` alone is already
            // strict: on audio whose language the prompt id does not name, the
            // model returns an empty transcript. Enabling the forced prefix
            // *weakens* that — mismatched prompts start emitting mangled
            // wrong-language text instead of nothing, which is the failure this
            // file's header refuses. So it costs the first word and buys
            // negative language safety.
            await manager.setForcedPrefix(false)

            // Overtaken while we were downloading or loading: drop this manager
            // rather than clobber a newer one. The two commits below stay
            // adjacent and await-free so the pair can never be seen half-applied.
            guard generation == loadGeneration else {
                PushLogger.log("NemotronMultilingualEngine: Discarded a superseded \(variant) load")
                return
            }

            self.manager = manager
            self.loadedVariant = variant
            PushLogger.log("NemotronMultilingualEngine: ✅ \(variant) build loaded for \(code)")
        } catch {
            PushLogger.log("NemotronMultilingualEngine: ❌ Failed to load model: \(error)")
            throw ParakeetEngineError.loadFailed(error.localizedDescription)
        }
    }

    /// Drops the resident model.
    ///
    /// Bumps the generation as well, so a load still parked on its download
    /// discards itself instead of quietly re-loading the engine moments after
    /// `ModelLoader` asked for it to go away.
    public func unloadModel() {
        loadGeneration &+= 1
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

    /// Milliseconds of digital silence prepended to every utterance.
    ///
    /// The encoder is cache-aware streaming, and at the start of a session its
    /// left context is a zeroed cache with `cache_len` seeded to 1 — it is told
    /// it has one frame of history that it does not really have. The opening
    /// ~100 ms of real speech is therefore encoded against a cold cache, and the
    /// user's first word is what pays for it. Handing the encoder silence to
    /// warm up on instead is the cheapest fix that treats the cause: over eight
    /// `say -v Luciana` pt-BR phrases the utterance's own first word survived
    /// 4/8 times with no lead-in and 8/8 with one; French went 5/6 to 6/6.
    ///
    /// 80, 160 and 240 ms all scored identically, so this sits in the middle of
    /// that plateau rather than on an edge where a slightly different clip could
    /// fall off it. The cost is 2560 samples — inaudible in the transcript, and
    /// it only occasionally pushes an utterance across a 2240 ms chunk boundary.
    private static let leadInSilence = [Float](repeating: 0, count: 160 * 16)

    /// Transcribes one utterance of 16 kHz mono float samples.
    ///
    /// Resets first: `finish()` clears the accumulated tokens but not the
    /// encoder's cache-aware state, so without this each utterance would decode
    /// with the tail of the previous one still in context.
    ///
    /// Not serialized against `loadModel`/`unloadModel`, by choice — the
    /// invariant `ModelLoader` has to honour instead is that no language switch
    /// or unload is issued mid-utterance. Guarding it here would mean an
    /// utterance could block a model swap, which is the worse failure.
    public func transcribeFloats(_ samples: [Float]) async throws -> String {
        guard let manager else {
            throw ParakeetEngineError.notInitialized
        }
        guard !samples.isEmpty else {
            throw ParakeetEngineError.emptyAudio
        }

        let start = Date()
        await manager.reset()
        _ = try await manager.process(samples: Self.leadInSilence + samples)
        let text = try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = Date().timeIntervalSince(start)

        // Duration and inference time only — never the transcript. The chosen
        // language is logged on the load path as a settings-style event, but
        // deliberately not here: next to an utterance's length and timing it
        // starts describing what was said, which a load line never does.
        PushLogger.log(String(
            format: "NemotronMultilingualEngine: Transcribed %.2fs audio in %.3fs (%d chars)",
            Double(samples.count) / 16000.0, elapsed, text.count))
        return text
    }
}

// MARK: - The prompt dictionary as a menu

/// Reduces a Nemotron model's raw `prompt_dictionary` to the list of languages
/// the picker offers.
///
/// Separate from the actor, and pure, because it is the one part of the
/// language story that can be checked without a 600 MB model: it is a function
/// from the JSON the model ships to the strings a user reads, and
/// `NemotronPromptDictionaryTests` runs it against the real dictionary's shape.
///
/// The dictionary is a *lookup table*. It is meant to be forgiving of whatever
/// a caller types, so it carries several spellings of the same prompt — the
/// `latin` build has 121 keys for 84 distinct prompt ids. Handing those keys to
/// a picker showed the user "English" and "English (United States)" as separate
/// choices for the same prompt, alongside `enGB` and `esES`, which the OS
/// cannot name at all and which were therefore rendered as themselves.
///
/// So: **one entry per prompt id, spelled the way a user should see it.**
public enum NemotronPromptDictionary {

    /// One `DictationLanguage` per distinct prompt id, most canonical spelling
    /// first, malformed spellings dropped.
    ///
    /// Everything here works on the *canonicalized* code — what
    /// `DictationLanguage.init` produces — never the raw key. The raw keys
    /// disagree with each other before canonicalization and agree after it
    /// (`no-NO` and `nb-NO` are both `nb-NO`), so de-duplicating on the raw key
    /// leaves pairs that look distinct here and collapse in the picker.
    public static func offeredLanguages(in dictionary: [String: Int]) -> [DictationLanguage] {
        // Best spelling for each prompt id.
        var best: [Int: Candidate] = [:]
        for (rawKey, promptId) in dictionary {
            guard let candidate = Candidate(rawKey: rawKey, dictionary: dictionary) else { continue }
            if let incumbent = best[promptId], !candidate.isPreferred(over: incumbent) { continue }
            best[promptId] = candidate
        }

        // Then across prompt ids, because canonicalization can make two of them
        // collide: the model carries Norwegian Bokmål twice, as `no`/`no-NO`
        // (27) and `nb`/`nb-NO` (103), and ICU folds the deprecated `no` onto
        // `nb`. Both ids would render "Norwegian Bokmål (Norway)", and the two
        // rows would be `==` — which breaks the Picker's identity-based tag and
        // the UserDefaults round-trip, not merely the look of the list.
        //
        // Only one of the two can be offered, and there is no choice about
        // which prompt it drives: whatever we offer goes back through
        // FluidAudio's own lookup, and `nb-NO` is a literal key of 103. Hence
        // `prefersLiteralKey` in the ordering — the survivor is the id that
        // actually answers to the code we hand out.
        var chosen: [String: (promptId: Int, candidate: Candidate)] = [:]
        for (promptId, candidate) in best {
            if let incumbent = chosen[candidate.code] {
                let wins = candidate.isPreferred(over: incumbent.candidate)
                    || (candidate.prefersLiteralKey == incumbent.candidate.prefersLiteralKey
                        && promptId < incumbent.promptId)
                if !wins { continue }
            }
            chosen[candidate.code] = (promptId, candidate)
        }

        return chosen.keys.map { DictationLanguage(code: $0) }.sorted()
    }

    /// One surviving spelling of one prompt id, with what is needed to rank it
    /// against the other spellings of the same prompt.
    struct Candidate {
        /// Canonicalized, i.e. exactly what `DictationLanguage` would hold.
        let code: String
        /// Lower is better; see `Rank`.
        let rank: Rank
        /// Whether `code` is a key of the dictionary verbatim, and so resolves
        /// back to this prompt id rather than to a neighbour's.
        let prefersLiteralKey: Bool

        enum Rank: Int, Comparable {
            /// `en-US`, `pt-PT`, `fr-CA` — a language and a region ICU has
            /// heard of together. The best spelling: it is the one that tells
            /// a user which Portuguese or which French a row means.
            case knownLocale = 0
            /// `en`, `pt`, `ar` — no region. Correct, just less specific than
            /// the sibling spelling usually sitting beside it.
            case languageOnly = 1
            /// `ar-AR` — a well-formed code for a locale that does not exist.
            /// Last choice; see `isKnownToICU`.
            case unknownLocale = 2

            static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        }

        /// Returns nil for a key that must never be offered.
        init?(rawKey: String, dictionary: [String: Int]) {
            // A real key (id 101) and the one option this app never offers —
            // see the engine's header. It would also fail the shape check
            // below, but dropping it on purpose beats dropping it by accident.
            guard rawKey.caseInsensitiveCompare("auto") != .orderedSame else { return nil }

            let code = DictationLanguage(code: rawKey).code
            let subtags = code.split(separator: "-").map(String.init)

            // The primary subtag is an ISO 639 language: two or three letters.
            // This is what rejects `enGB` and `esES` — canonicalization does
            // not repair them (they come out `engb` and `eses`), and ICU has no
            // name for either, so the picker showed the user the raw string.
            guard let language = subtags.first,
                  (2...3).contains(language.count),
                  language.allSatisfy({ $0.isASCII && $0.isLetter && $0.isLowercase })
            else { return nil }

            let region = subtags.dropFirst().first(where: Self.looksLikeRegion)

            // A two-letter region has to be a real country. This is what
            // rejects the invented regionals — `zh-ZH`, `ja-JA`, `ko-KO`,
            // `hi-HI` — where the "region" is the language code shouted: none
            // of ZH, JA, KO, HI is an ISO 3166 country, macOS cannot name them
            // either, and all four reached the picker as raw codes. Each
            // shares its prompt with a proper spelling (`zh-CN`, `ja-JP`,
            // `ko-KR`, `hi-IN`), so nothing is lost with them.
            //
            // Careful: `so-SO`, `th-TH`, `az-AZ`, `uz-UZ`, `id-ID`, `mt-MT`,
            // `to-TO` and `rw-RW` look like exactly the same mistake and are
            // not — Somalia, Thailand, Azerbaijan, Uzbekistan, Indonesia,
            // Malta, Tonga and Rwanda are real, and each of those eight is the
            // *only* key for its prompt. Testing the region rather than the
            // repeated letters is what keeps those eight languages.
            if let region, region.count == 2, !Locale.Region(region).isISORegion { return nil }

            self.code = code
            self.prefersLiteralKey = dictionary[code] != nil
            switch region {
            case .none: self.rank = .languageOnly
            case .some(let region):
                self.rank = Self.isKnownToICU(language: language, region: region)
                    ? .knownLocale : .unknownLocale
            }
        }

        /// Whether macOS knows of any locale pairing this language with this
        /// region — the test that separates a region worth showing from one
        /// that is merely well-formed.
        ///
        /// It exists for `ar-AR`. `AR` *is* Argentina, so it passes the ISO
        /// check above, and macOS names that prompt "Arabic (Argentina)" with
        /// a straight face. The model plainly means Arabic; `ar` shares the
        /// prompt, so ranking `ar-AR` last picks up the honest spelling.
        ///
        /// A tempting shortcut is to look for a region that repeats its
        /// language, since `ar-AR` does. Do not: so do `fr-FR`, `pt-PT`,
        /// `de-DE`, `it-IT`, `nl-NL`, `pl-PL`, `tr-TR`, `ru-RU`, `ro-RO`,
        /// `hu-HU`, `sk-SK`, `hr-HR`, `bg-BG`, `lt-LT`, `lv-LV` and `fi-FI`.
        /// That rule was written, and it demoted all sixteen — leaving
        /// "Portuguese" sitting next to "Portuguese (Brazil)", where a reader
        /// has no way to tell that the first one is the European model.
        ///
        /// This is a demotion and never a rejection, because it also fires on
        /// three regions the model gets right and ICU simply does not ship:
        /// `ay-BO` (Aymara/Bolivia), `nah-MX` (Nahuatl/Mexico) and `or-KE`.
        /// Each is the only key for its prompt, so rejecting would delete
        /// three languages to tidy up one.
        private static func isKnownToICU(language: String, region: String) -> Bool {
            knownLocales.contains("\(language)-\(region)")
        }

        /// Every language–region pair macOS ships a locale for. Built once:
        /// `Locale.availableIdentifiers` is ~900 strings to parse and the
        /// answer cannot change while the process runs.
        private static let knownLocales: Set<String> = {
            var pairs = Set<String>()
            for identifier in Locale.availableIdentifiers {
                let locale = Locale(identifier: identifier)
                guard let language = locale.language.languageCode?.identifier,
                      let region = locale.region?.identifier else { continue }
                pairs.insert("\(language)-\(region)")
            }
            return pairs
        }()

        /// Region subtags are two letters or three digits (`es-419`). Script
        /// subtags (`zh-Hant`) and variants are neither and are passed over
        /// rather than rejected — no build ships one today, and a future one
        /// would be a spelling to keep, not to drop.
        private static func looksLikeRegion(_ subtag: String) -> Bool {
            (subtag.count == 2 && subtag.allSatisfy { $0.isASCII && $0.isLetter && $0.isUppercase })
                || (subtag.count == 3 && subtag.allSatisfy(\.isNumber))
        }

        /// Total and deterministic: a dictionary has no order, so ties broken
        /// by anything less would let the offered list change between runs.
        func isPreferred(over other: Self) -> Bool {
            if rank != other.rank { return rank < other.rank }
            if prefersLiteralKey != other.prefersLiteralKey { return prefersLiteralKey }
            if code.count != other.code.count { return code.count < other.code.count }
            return code < other.code
        }
    }
}
