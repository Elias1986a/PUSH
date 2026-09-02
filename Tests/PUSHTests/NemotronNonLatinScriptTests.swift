import XCTest
import AVFoundation
@testable import PUSHCore

/// Whether the prompt ids only the `multilingual` build can serve actually
/// transcribe their own language, and in their own script.
///
/// Until this file existed nobody had ever run audio through one of them. The
/// picker offered sixty-odd languages that no build on disk had been asked to
/// say a word in, so a user choosing Japanese paid a ~640 MB download for an
/// unknown outcome. These eight are the ones that were checked and work; the
/// ones that do not are suppressed in `NemotronPromptDictionary` and their
/// evidence is recorded there.
///
/// One clip per language, `say`-synthesized rather than recorded, so the suite
/// stays hermetic. The assertion is deliberately weak — non-empty, and in the
/// right script — because anything stronger is an opinion about how well this
/// model hears a robot voice, and would break on every FluidAudio bump for no
/// good reason. What is being defended is "Korean comes back as Hangul", not a
/// word-error rate.
///
/// Needs the ~640 MB `multilingual` build and skips cleanly without it.
/// Nothing here logs or asserts on transcript text; lengths and scripts only.
final class NemotronNonLatinScriptTests: XCTestCase {

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
        let aiff = dir.appendingPathComponent("push-script-\(tag).aiff")
        let wav = dir.appendingPathComponent("push-script-\(tag).wav")
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

    /// The scripts this file can tell apart, by the Unicode ranges that define
    /// them. Only what is needed below — this is not a general classifier.
    private enum Script: String, CaseIterable {
        case latin, greek, cyrillic, hebrew, arabic, devanagari, kana, han, hangul

        var ranges: [ClosedRange<UInt32>] {
            switch self {
            case .latin: return [0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF]
            case .greek: return [0x370...0x3FF, 0x1F00...0x1FFF]
            case .cyrillic: return [0x400...0x52F]
            case .hebrew: return [0x590...0x5FF]
            case .arabic: return [0x600...0x6FF, 0x750...0x77F, 0x8A0...0x8FF]
            case .devanagari: return [0x900...0x97F]
            case .kana: return [0x3040...0x30FF]
            case .han: return [0x3400...0x4DBF, 0x4E00...0x9FFF]
            case .hangul: return [0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF]
            }
        }
    }

    /// How many of `text`'s letters belong to each script. Letters only:
    /// digits, spaces and punctuation say nothing about which script this is.
    private func histogram(_ text: String) -> [Script: Int] {
        var counts: [Script: Int] = [:]
        for scalar in text.unicodeScalars {
            for script in Script.allCases where script.ranges.contains(where: { $0.contains(scalar.value) }) {
                counts[script, default: 0] += 1
            }
        }
        return counts
    }

    /// A language, a macOS voice that speaks it, and the script its transcript
    /// must be written in. Every voice here is one `say -v '?'` reports on a
    /// stock macOS install — the test skips rather than fails if one is absent.
    private static let cases: [(code: String, voice: String, scripts: Set<Script>, text: String)] = [
        ("ja-JP", "Kyoko", [.kana, .han],
         "明日の会議は九時ちょうどに始まりますので、少し早めに来てください。"),
        ("ko-KR", "Yuna", [.hangul],
         "내일 회의는 아홉 시 정각에 시작하니까 조금 일찍 와 주세요."),
        ("zh-CN", "Tingting", [.han],
         "明天的会议九点整开始，请大家提前十分钟到达。"),
        ("ru-RU", "Milena", [.cyrillic],
         "Завтрашняя встреча начинается ровно в девять часов, поэтому лучше прийти пораньше."),
        ("uk-UA", "Lesya", [.cyrillic],
         "Завтрашня зустріч починається рівно о дев'ятій годині, тому краще прийти раніше."),
        ("el-GR", "Melina", [.greek],
         "Η αυριανή συνάντηση αρχίζει στις εννέα ακριβώς, γι' αυτό είναι καλύτερα να έρθουμε νωρίς."),
        ("he-IL", "Carmit", [.hebrew],
         "הפגישה של מחר מתחילה בתשע בדיוק, ולכן כדאי להגיע מוקדם."),
        ("ar", "Majed", [.arabic],
         "اجتماع الغد يبدأ في الساعة التاسعة تماما، لذلك من الأفضل الحضور مبكرا."),
        ("hi-IN", "Lekha", [.devanagari],
         "कल की बैठक ठीक नौ बजे शुरू होगी, इसलिए थोड़ा जल्दी आना बेहतर होगा।"),
    ]

    // MARK: - The test

    /// One engine, one build, a prompt swap between languages — the cheap path
    /// `loadModel` takes for two languages in the same vocabulary group, and
    /// the one the app itself uses when a user changes language.
    func testEachNonLatinPromptAnswersInItsOwnScript() async throws {
        guard NemotronMultilingualEngine.isModelDownloaded(for: "ja-JP") else {
            throw XCTSkip("Nemotron multilingual build not on disk — skipping script tests")
        }

        var clips: [(code: String, scripts: Set<Script>, samples: [Float])] = []
        for testCase in Self.cases {
            guard let url = Self.synthesize(testCase.text, voice: testCase.voice,
                                            tag: testCase.code) else {
                throw XCTSkip("could not synthesize with `say -v \(testCase.voice)`")
            }
            clips.append((testCase.code, testCase.scripts, try Self.samples(at: url)))
        }

        let engine = NemotronMultilingualEngine()
        for clip in clips {
            try await engine.loadModel(languageCode: clip.code)
            let text = try await engine.transcribeFloats(clip.samples)

            XCTAssertFalse(text.isEmpty, "\(clip.code) returned nothing for speech in its own language")

            // `<unk>` is how a prompt that cannot spell its language fails: it
            // decodes confidently into a token the vocabulary has no character
            // for. Counted rather than tolerated, because a transcript full of
            // it is worse for a user than an empty one — it looks like output.
            XCTAssertFalse(text.contains("<unk>"),
                           "\(clip.code) returned unknown tokens")

            let counts = histogram(text)
            let total = counts.values.reduce(0, +)
            XCTAssertGreaterThan(total, 0, "\(clip.code) returned no letters at all")

            let inScript = clip.scripts.reduce(0) { $0 + (counts[$1] ?? 0) }
            XCTAssertGreaterThan(
                Double(inScript), Double(total) * 0.8,
                "\(clip.code) answered in the wrong script: \(inScript) of \(total) letters were "
                + clip.scripts.map(\.rawValue).sorted().joined(separator: "/"))
        }
    }
}
