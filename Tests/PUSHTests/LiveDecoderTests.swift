import XCTest
import FluidAudio
@testable import PUSHCore

/// `LiveDecoder` against a fake engine that "hears" a fixed script: every
/// sample holds its own time in seconds, so a window knows where it sits in
/// the take and returns exactly the words spoken inside it. The model-backed
/// check is the compare tool's replay of real readings.
final class LiveDecoderTests: XCTestCase {

    private static let rate = SentenceAlignedWindows.sampleRate

    /// 40 s of speech: sentences of five words, 0.5 s apart, a full stop and
    /// then a 1 s pause. Word i of sentence s is "Ws" capitalised at the start.
    private struct Word { let text: String; let start: Double }
    private static let script: [Word] = {
        var words: [Word] = []
        var t = 0.3
        var sentence = 0
        while t < 39 {
            for i in 0..<5 {
                words.append(Word(text: (i == 0 ? " S" : " w") + "\(sentence)w\(i)", start: t))
                t += 0.5
            }
            words.append(Word(text: ".", start: t - 0.1))
            t += 1.0
            sentence += 1
        }
        return words
    }()

    private static let audio: [Float] = (0..<Int(40 * rate)).map { Float(Double($0) / rate) }

    private static let window: LiveDecoder.Window = { chunk in
        let from = Double(chunk.first ?? 0), to = Double(chunk.last ?? 0)
        let tokens = script.filter { $0.start >= from && $0.start + 0.2 <= to }.map {
            TokenTiming(token: $0.text, tokenId: 0, startTime: $0.start - from,
                        endTime: $0.start - from + 0.1, confidence: 1)
        }
        return .init(text: tokens.map(\.token).joined(), tokens: tokens)
    }
    private static let whole: LiveDecoder.Whole = { _ in "(whole)" }

    private var expected: String {
        // The same edge the fake engine uses: a word needs 0.2 s of audio.
        Self.script.filter { $0.start + 0.2 <= Double(Self.audio.last!) }.map(\.text).joined()
            .trimmingCharacters(in: .whitespaces)
    }

    private func decoder() -> LiveDecoder {
        LiveDecoder(model: .parakeetUltra, leadIn: 0, window: Self.window, whole: Self.whole)
    }

    func testLiveTextIsTheWholeScriptOnceInOrder() async {
        let live = decoder()
        var i = 0
        while i < Self.audio.count {
            let end = min(i + 1_365, Self.audio.count)
            await live.append(Array(Self.audio[i..<end]))
            await live.settle()
            i = end
        }
        let kept = await live.progress.kept
        XCTAssertGreaterThan(kept, 5, "sentences should be kept while speaking")
        let remaining = await live.progress.remainingSeconds
        XCTAssertLessThan(remaining, 10)
        let text = await live.finish(expectedSamples: Self.audio.count)
        XCTAssertEqual(text, expected)
        let offline = try? await SentenceAlignedWindows.transcribe(
            Self.audio, window: Self.window, whole: Self.whole)
        XCTAssertEqual(text, offline)
    }

    func testMatchesTheReleaseTimePath() async throws {
        let offline = try await SentenceAlignedWindows.transcribe(
            Self.audio, window: Self.window, whole: Self.whole)
        XCTAssertEqual(offline, expected)
    }

    func testARecordingItDidNotHearIsRefused() async {
        let live = decoder()
        await live.append(Array(Self.audio[0..<16_000]))
        let text = await live.finish(expectedSamples: 32_000)
        XCTAssertNil(text)
    }

    func testCancelledDecoderIgnoresMoreAudio() async {
        let live = decoder()
        await live.cancel()
        await live.append(Array(Self.audio[0..<16_000]))
        let count = await live.sampleCount
        XCTAssertEqual(count, 0)
    }
}
