import XCTest
import AVFoundation
@testable import PUSHCore

/// End-to-end guards on what `NemotronMultilingualEngine` does to one utterance.
///
/// Everything here needs the ~600 MB `latin` build on disk and skips cleanly
/// without it, so the suite stays fast for anyone who has not downloaded it.
/// Speech is synthesized with `say` rather than shipped as a fixture or read
/// aloud by anyone — the same trick `AppleSpeechSmokeTest` uses.
///
/// Nothing here asserts a whole transcript. The engine's output is a model's
/// opinion about audio and pinning it exactly would fail on every FluidAudio
/// bump for no good reason; these assert invariants that held before the bug
/// and broke during it.
final class NemotronMultilingualUtteranceTests: XCTestCase {

    // MARK: - Fixtures

    private static func run(_ launchPath: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// `say` + `afconvert` to the 16 kHz mono Float32 the engines are fed.
    private static func synthesize(_ text: String, voice: String, tag: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let aiff = dir.appendingPathComponent("push-nemo-\(tag).aiff")
        let wav = dir.appendingPathComponent("push-nemo-\(tag).wav")
        if FileManager.default.fileExists(atPath: wav.path) { return wav }
        guard run("/usr/bin/say", ["-v", voice, "-o", aiff.path, text]),
              run("/usr/bin/afconvert",
                  ["-f", "WAVE", "-d", "LEF32@16000", "-c", "1", aiff.path, wav.path])
        else { return nil }
        return wav
    }

    /// `afconvert` already wrote the engine's format, so this is the one case
    /// `compare`'s `AudioFileLoader` handles with no resample or downmix.
    private static func samples(at url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// Skips rather than fails: the build is a ~600 MB download nobody should
    /// have to make to run the unit tests.
    private func requireModel() throws {
        guard NemotronMultilingualEngine.isModelDownloaded(for: "pt-BR") else {
            throw XCTSkip("Nemotron latin build not on disk — skipping engine tests")
        }
    }

    private func clip(_ text: String, voice: String, tag: String) throws -> [Float] {
        guard let url = Self.synthesize(text, voice: voice, tag: tag) else {
            throw XCTSkip("could not synthesize a clip with `say -v \(voice)`")
        }
        return try Self.samples(at: url)
    }

    /// Lowercased, unaccented, letters only — so a comparison survives the
    /// model's punctuation and diacritic choices, which are not what is on test.
    private static func firstWord(_ s: String) -> String {
        (s.split(separator: " ").first.map(String.init) ?? "")
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter }
    }

    // Sub-chunk (< 2240 ms) and multi-chunk, because the engine pads a partial
    // final chunk and the two paths are worth covering separately.
    private static let shortPhrase = "Bom dia, tudo bem?"
    private static let longPhrase =
        "Bom dia, eu preciso enviar um relatorio para a equipe hoje de tarde."

    // MARK: - The reported bug

    /// The bug as reported: transcripts collapsing to a few characters after the
    /// first utterance following a language switch. They do not — the engine is
    /// deterministic, and this holds it that way.
    ///
    /// The input is byte-identical on every pass, so any difference between run 1
    /// and runs 2–4 would be state surviving inside the engine: `finish()` clears
    /// the accumulated tokens but not the encoder's cache-aware state, and it is
    /// `transcribeFloats`' leading `reset()` that clears the rest. Delete that
    /// `reset()` and this test is what notices.
    ///
    /// Asserted as a proportion of run 1 rather than as equality: CoreML is
    /// deterministic in practice on one machine, but pinning that across every
    /// macOS and ANE revision would buy a flaky test instead of a real guard. A
    /// collapse of the kind reported is a 60–90% drop and clears this by miles.
    func testRepeatedUtterancesDoNotDegrade() async throws {
        try requireModel()
        let samples = try clip(Self.longPhrase, voice: "Luciana", tag: "repeat-long")

        let engine = NemotronMultilingualEngine()
        try await engine.loadModel(languageCode: "pt-BR")

        let first = try await engine.transcribeFloats(samples)
        XCTAssertFalse(first.isEmpty, "engine returned nothing for real Portuguese speech")

        for run in 2...4 {
            let text = try await engine.transcribeFloats(samples)
            XCTAssertGreaterThanOrEqual(
                Double(text.count), Double(first.count) * 0.8,
                "run \(run) returned \(text.count) chars against run 1's \(first.count) — "
                + "the same audio decoded worse, so something survived the reset")
        }
    }

    /// The same invariant for a sub-chunk utterance, which is where the reported
    /// collapse would have hurt most: at 2240 ms per chunk a 1.5 s utterance is
    /// one padded chunk, so a few lost tokens are the whole transcript.
    func testRepeatedShortUtterancesDoNotDegrade() async throws {
        try requireModel()
        let samples = try clip(Self.shortPhrase, voice: "Luciana", tag: "repeat-short")
        XCTAssertLessThan(Double(samples.count) / 16000.0, 2.24, "clip should be sub-chunk")

        let engine = NemotronMultilingualEngine()
        try await engine.loadModel(languageCode: "pt-BR")

        let first = try await engine.transcribeFloats(samples)
        XCTAssertFalse(first.isEmpty, "engine returned nothing for a short utterance")

        for run in 2...4 {
            let text = try await engine.transcribeFloats(samples)
            XCTAssertGreaterThanOrEqual(
                Double(text.count), Double(first.count) * 0.8,
                "short run \(run) returned \(text.count) chars against run 1's \(first.count)")
        }
    }

    /// Switching language in-build must not degrade later utterances either —
    /// the cheap path in `loadModel` reuses the resident manager, so a switch is
    /// the other way stale state could reach an utterance.
    func testLanguageSwitchDoesNotDegradeLaterUtterances() async throws {
        try requireModel()
        let samples = try clip(Self.longPhrase, voice: "Luciana", tag: "repeat-long")

        let engine = NemotronMultilingualEngine()
        try await engine.loadModel(languageCode: "pt-BR")
        let before = try await engine.transcribeFloats(samples)

        try await engine.loadModel(languageCode: "fr-FR")
        try await engine.loadModel(languageCode: "pt-BR")

        let after = try await engine.transcribeFloats(samples)
        XCTAssertGreaterThanOrEqual(
            Double(after.count), Double(before.count) * 0.8,
            "the same audio decoded worse after a round trip through another language")
    }

    // MARK: - The bug actually found

    private static let headPhrases = [
        "Bom dia, tudo bem?",
        "Preciso falar com voce agora.",
        "Vamos marcar a reuniao para amanha.",
        "Obrigado pela ajuda de ontem.",
        "Onde fica a estacao mais proxima?",
        "Hoje esta muito calor aqui.",
        "Eu gosto muito desse restaurante novo.",
        "Pode me enviar o documento por favor?",
    ]

    /// The utterance's first word has to survive.
    ///
    /// This is the regression that matters. Two separate faults ate the opening
    /// word of every utterance: FluidAudio's forced language prefix, which seeds
    /// the decoder into a state that emits a spurious "a"/"a gente" in place of
    /// the real first token, and the encoder's cold cache-aware left context at
    /// the start of a session. On these eight phrases the first word survived
    /// 0/8 times with the prefix on, 4/8 with it off and no lead-in silence, and
    /// 8/8 with the engine as it now stands.
    ///
    /// Scored over a set with a 6/8 floor rather than asserted per phrase: this
    /// is the one place a transcript is compared against known words, and a
    /// single phrase the model happens to mishear should not fail the suite.
    /// Either fault regressing takes this to 0/8 or 4/8, both well clear.
    func testFirstWordOfEachUtteranceSurvives() async throws {
        try requireModel()
        let engine = NemotronMultilingualEngine()
        try await engine.loadModel(languageCode: "pt-BR")

        var hits = 0
        var scored = 0
        for (i, phrase) in Self.headPhrases.enumerated() {
            guard let url = Self.synthesize(phrase, voice: "Luciana", tag: "head\(i)") else { continue }
            let samples = try Self.samples(at: url)
            let text = try await engine.transcribeFloats(samples)
            scored += 1
            if Self.firstWord(text) == Self.firstWord(phrase) { hits += 1 }
        }

        try XCTSkipIf(scored == 0, "could not synthesize any clip with `say -v Luciana`")
        XCTAssertGreaterThanOrEqual(
            hits, Int(Double(scored) * 0.75),
            "only \(hits)/\(scored) utterances kept their first word — the head of the "
            + "utterance is being eaten again (forced prefix re-enabled, or lead-in lost)")
    }
}
