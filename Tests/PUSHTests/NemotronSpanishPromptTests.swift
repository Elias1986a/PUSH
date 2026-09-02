import XCTest
import AVFoundation
@testable import PUSHCore

/// Whether Spanish prompt id 2 (`es-ES`) is silent.
///
/// It is not, and this file exists because a single synthesized clip said it
/// was: prompt 2 returned nothing while prompt 3 (`es` / `es-US`) transcribed
/// the same audio, which reads exactly like a dead prompt embedding and would
/// have justified hiding "Spanish (Spain)" from the picker.
///
/// Seven clips across four voices and both accent groups say otherwise. Prompt
/// 2 transcribed six of them, including all three Latin-American ones, and the
/// clip it failed on is one that *ten of ten* prompt ids fail on — prompt 3
/// included. The original observation was a bad clip, not a bad prompt, and
/// hiding Spain's Spanish over it would have been a wrongly-hidden language.
///
/// So what is asserted here is the claim that was actually in doubt, in the
/// weakest form that still catches the bug: **prompt 2 is never silent where
/// prompt 3 speaks.** Not that either transcribes any particular clip — that
/// is the model's opinion about synthesized audio and it would break on every
/// FluidAudio bump for no good reason.
///
/// Needs the ~600 MB `latin` build and skips cleanly without it. Nothing here
/// prints or asserts on transcript text; lengths only.
final class NemotronSpanishPromptTests: XCTestCase {

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

    private static func synthesize(_ text: String, voice: String, tag: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let aiff = dir.appendingPathComponent("push-es-\(tag).aiff")
        let wav = dir.appendingPathComponent("push-es-\(tag).wav")
        if FileManager.default.fileExists(atPath: wav.path) { return wav }
        guard run("/usr/bin/say", ["-v", voice, "-o", aiff.path, text]),
              run("/usr/bin/afconvert",
                  ["-f", "WAVE", "-d", "LEF32@16000", "-c", "1", aiff.path, wav.path])
        else { return nil }
        return wav
    }

    private static func samples(at url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// Both accent groups, two voices each. `say` names its Spain and Mexico
    /// variants identically for most voices, hence the parenthesised forms.
    private static let clips: [(tag: String, voice: String, text: String)] = [
        ("grandma", "Grandma (Spanish (Spain))",
         "La reunión de mañana empieza a las nueve en punto, así que conviene llegar con tiempo."),
        ("rocko", "Rocko (Spanish (Spain))",
         "Me gustaría reservar una mesa para cuatro personas el viernes por la noche, si es posible."),
        ("paulina", "Paulina",
         "El clima de hoy está bastante agradable y tengo ganas de salir a caminar por el parque."),
        ("sandy", "Sandy (Spanish (Mexico))",
         "La reunión de mañana empieza a las nueve en punto, así que conviene llegar con tiempo."),
    ]

    // MARK: - The test

    /// `es-ES` resolves to prompt 2 and `es-US` to prompt 3, so setting the
    /// language is all it takes to compare the two — and it exercises the path
    /// the app actually uses rather than `setPromptId` behind its back.
    func testSpainsSpanishIsNeverSilentWhereLatinAmericasSpeaks() async throws {
        guard NemotronMultilingualEngine.isModelDownloaded(for: "es-ES") else {
            throw XCTSkip("Nemotron latin build not on disk — skipping Spanish prompt tests")
        }

        var audio: [(tag: String, samples: [Float])] = []
        for clip in Self.clips {
            guard let url = Self.synthesize(clip.text, voice: clip.voice, tag: clip.tag) else {
                throw XCTSkip("could not synthesize with `say -v \(clip.voice)`")
            }
            audio.append((clip.tag, try Self.samples(at: url)))
        }

        // One engine, one build, one prompt swap between the two passes — the
        // cheap path `loadModel` takes for two languages in the same build.
        let engine = NemotronMultilingualEngine()

        try await engine.loadModel(languageCode: "es-US")
        var latinAmerica: [String: Int] = [:]
        for clip in audio {
            latinAmerica[clip.tag] = try await engine.transcribeFloats(clip.samples).count
        }

        try await engine.loadModel(languageCode: "es-ES")
        var spain: [String: Int] = [:]
        for clip in audio {
            spain[clip.tag] = try await engine.transcribeFloats(clip.samples).count
        }

        // The claim under test. A dead prompt embedding is silent everywhere;
        // prompt 2 is silent only where prompt 3 is too.
        for clip in audio {
            let other = latinAmerica[clip.tag] ?? 0
            guard other > 0 else { continue }
            XCTAssertGreaterThan(
                spain[clip.tag] ?? 0, 0,
                "es-ES returned nothing on \(clip.tag) where es-US returned \(other) characters")
        }

        // And it is not merely non-silent by a character or two: what prompt 2
        // returns is the same size of transcript as prompt 3, which is what
        // separates "works" from "emits one token and gives up".
        for clip in audio where (latinAmerica[clip.tag] ?? 0) > 0 {
            let spainCount = Double(spain[clip.tag] ?? 0)
            let otherCount = Double(latinAmerica[clip.tag] ?? 0)
            XCTAssertGreaterThan(
                spainCount, otherCount * 0.5,
                "es-ES returned \(Int(spainCount)) characters on \(clip.tag) against es-US's \(Int(otherCount))")
        }

        // Guards the guard: if every clip came back empty the loop above is
        // vacuous and would pass over a genuinely broken engine.
        XCTAssertGreaterThan(latinAmerica.values.filter { $0 > 0 }.count, 2,
                             "es-US transcribed almost nothing — the clips or the engine are broken")
        XCTAssertGreaterThan(spain.values.filter { $0 > 0 }.count, 2,
                             "es-ES transcribed almost nothing")
    }
}
