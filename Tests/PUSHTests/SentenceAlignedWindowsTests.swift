import XCTest
import FluidAudio
@testable import PUSHCore

/// Where long dictation is cut into encoder windows. The model-backed check is
/// the saved benchmark readings through the compare tool; these pin the rules.
final class SentenceAlignedWindowsTests: XCTestCase {

    /// Tokens as the engines report them: a leading space starts a word.
    private func tokens(_ spec: [(String, Double, Double)]) -> [TokenTiming] {
        spec.map { TokenTiming(token: $0.0, tokenId: 0, startTime: $0.1, endTime: $0.2, confidence: 1) }
    }

    func testCutsInThePauseAfterTheLastSentenceEnd() {
        let t = tokens([(" Let", 0.2, 0.3), ("'s", 0.3, 0.4), (" go", 0.4, 0.6), (".", 0.6, 0.7),
                        (" Then", 2.4, 2.6), (" we", 2.6, 2.8), (" eat", 2.8, 3.0), (".", 3.0, 3.1),
                        (" After", 4.1, 4.3), (" that", 4.3, 4.5)])
        let cut = SentenceAlignedWindows.cut(in: t, windowSeconds: 15)
        XCTAssertEqual(cut?.through, 7)
        XCTAssertEqual(cut?.at ?? 0, 3.6, accuracy: 0.001)
    }

    /// "4.30 p.m." and "15.2" hold dots that are not sentence ends, and the
    /// model's own full stop on a truncated window is not trusted.
    func testIgnoresDecimalsLowercaseAndTheWindowsLastSecondAndAHalf() {
        let t = tokens([(" at", 2.0, 2.1), (" 4", 2.1, 2.2), (".", 2.2, 2.3), ("30", 2.3, 2.4),
                        (" p", 2.4, 2.5), (".", 2.5, 2.6), ("m", 2.6, 2.7), (".", 2.7, 2.8),
                        (" since", 2.9, 3.0), (" it", 3.0, 3.1), (".", 3.1, 3.2),
                        (" So", 13.8, 14.0), (" 15", 14.0, 14.2), (".", 14.2, 14.3)])
        XCTAssertNil(SentenceAlignedWindows.cut(in: t, windowSeconds: 15))
    }

    func testNoCutTooCloseToTheWindowStart() {
        let t = tokens([(" Hi", 0.2, 0.4), (".", 0.4, 0.5), (" Bye", 0.9, 1.1)])
        XCTAssertNil(SentenceAlignedWindows.cut(in: t, windowSeconds: 15))
    }

    /// The lead-in's tokens belong to the previous window, including a full
    /// stop emitted a moment late.
    func testLeadInDropsThePreviousSentencesStragglers() {
        let t = tokens([(" team", 0.3, 0.6), (".", 1.02, 1.1), (" We", 1.3, 1.4), ("'ve", 1.4, 1.5)])
        let kept = SentenceAlignedWindows.afterLeadIn(t, leadIn: 1.0)
        XCTAssertEqual(kept.map(\.token).joined(), " We've")
        XCTAssertEqual(SentenceAlignedWindows.afterLeadIn(t, leadIn: 0).count, 4)
    }

    func testSentencePieceWordMarkerReadsAsASpace() {
        let t = tokens([("\u{2581}Could", 0, 0.1)])
        XCTAssertEqual(SentenceAlignedWindows.piece(t[0]), " Could")
    }
}
