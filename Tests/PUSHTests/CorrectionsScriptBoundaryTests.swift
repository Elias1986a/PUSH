import XCTest
@testable import PUSH
@testable import PUSHCore

/// The dictionary's word-boundary rule across writing systems.
///
/// Both replacement lanes wrap the search term in `\b`, which is defined as a
/// transition between a word character and a non-word character. Japanese,
/// Chinese and Thai write without inter-word spaces, so a term sitting inside a
/// longer run has a word character on both sides and `\b` never holds — the
/// entry saves fine and then silently does nothing.
final class CorrectionsScriptBoundaryTests: XCTestCase {

    private typealias Correction = CorrectionsStore.Correction

    /// Approves every candidate, so the contextual lane's *matching* can be
    /// tested without the heuristic gate's English-only cues deciding the
    /// outcome.
    private struct ApproveAll: VerdictSource {
        func judge(sentence: String, candidates: [CorrectionCandidate]) async -> [CorrectionVerdict] {
            Array(repeating: .apply, count: candidates.count)
        }
    }

    // MARK: - Entries that start or end with a symbol

    /// The user's own entry: "&" heard, "AMP" wanted. `\b` before an ampersand
    /// needs a letter in front of it, so it never matched a spoken "&".
    func testAnAmpersandEntryFiresOnAStandaloneAmpersand() {
        let corrections = [Correction(wrong: "&", right: "AMP")]
        XCTAssertEqual(CorrectionsStore.applyReplacements(corrections, to: "Tom & Jerry"), "Tom AMP Jerry")
        XCTAssertEqual(CorrectionsStore.applyReplacements(corrections, to: "Tom &"), "Tom AMP")
        XCTAssertEqual(CorrectionsStore.applyReplacements(corrections, to: "& Jerry"), "AMP Jerry")
    }

    /// Not inside another term: AT&T and R&D are not the word the user means.
    func testAnAmpersandEntryLeavesAmpersandsInsideWordsAlone() {
        let corrections = [Correction(wrong: "&", right: "AMP")]
        XCTAssertEqual(CorrectionsStore.applyReplacements(corrections, to: "AT&T and R&D"), "AT&T and R&D")
    }

    func testAnEntryEndingInAFullStopFiresBeforeASpace() {
        let corrections = [Correction(wrong: "dr.", right: "Doctor")]
        XCTAssertEqual(CorrectionsStore.applyReplacements(corrections, to: "see dr. Lee"), "see Doctor Lee")
    }

    func testAnEntryWithASymbolInsideStillMatchesWholeWords() {
        let corrections = [Correction(wrong: "c++", right: "C++")]
        XCTAssertEqual(CorrectionsStore.applyReplacements(corrections, to: "I write c++ daily"), "I write C++ daily")
        XCTAssertEqual(CorrectionsStore.applyReplacements(corrections, to: "abc++"), "abc++")
    }

    /// Saying "ampersand" gives "ampersand" at the dictionary and "&" only after
    /// the formatting, so a symbol entry needs its own pass after it.
    func testASpokenAmpersandReachesASymbolEntryAfterFormatting() {
        let corrections = [Correction(wrong: "&", right: "AMP"), Correction(wrong: "jerry", right: "Gerry")]
        let first = CorrectionsStore.applyReplacements(corrections.filter { $0.kind == .always }, to: "Tom ampersand jerry")
        XCTAssertEqual(first, "Tom ampersand Gerry")
        let formatted = TranscriptionPipeline.smartSymbols(first)
        XCTAssertEqual(formatted, "Tom & Gerry")
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(CorrectionsStore.symbolOnlyEntries(corrections), to: formatted),
            "Tom AMP Gerry")
    }

    func testOnlySymbolOnlyAlwaysEntriesGetTheSecondPass() {
        let entries = [Correction(wrong: "&", right: "AMP"), Correction(wrong: "c++", right: "C++"),
                       Correction(wrong: "@", right: "at", kind: .contextual), Correction(wrong: "dr.", right: "Doctor")]
        XCTAssertEqual(CorrectionsStore.symbolOnlyEntries(entries).map(\.wrong), ["&"])
    }

    func testTheContextualLaneMatchesSymbolEntriesToo() async {
        let corrections = [Correction(wrong: "&", right: "AMP", kind: .contextual)]
        let result = await CorrectionsStore.applyContextAware(corrections, to: "Tom & Jerry", using: ApproveAll())
        XCTAssertEqual(result, "Tom AMP Jerry")
    }

    // MARK: - Scripts written without spaces

    func testJapaneseEntryInsideARunOfKanaIsReplaced() {
        let corrections = [Correction(wrong: "こんにちわ", right: "こんにちは")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "今日はこんにちわと言いました"),
            "今日はこんにちはと言いました")
    }

    func testChineseEntryInsideARunOfIdeographsIsReplaced() {
        let corrections = [Correction(wrong: "沈阳", right: "瀋陽")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "我住在沈阳市中心"),
            "我住在瀋陽市中心")
    }

    func testThaiEntryInsideARunOfThaiIsReplaced() {
        let corrections = [Correction(wrong: "สวัสดี", right: "หวัดดี")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "ฉันพูดสวัสดีทุกวัน"),
            "ฉันพูดหวัดดีทุกวัน")
    }

    /// The other half of the same bug: the term is Latin but its neighbours are
    /// kana, so there is no word-character transition there either. This is the
    /// common case for a brand or product name dictated in Japanese.
    func testLatinEntrySurroundedByJapaneseIsReplaced() {
        let corrections = [Correction(wrong: "Hammer", right: "Hamer")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "私はHammerを使う"),
            "私はHamerを使う")
    }

    /// Dropping the boundary for a non-spaced script is a substring match, so a
    /// term also fires inside a longer compound. Pinned deliberately: without
    /// spaces there is no way to tell "the word 東京" from "東京 inside 東京都",
    /// and a correction that never fires is the worse failure.
    func testNonSpacedEntryAlsoFiresInsideACompound() {
        let corrections = [Correction(wrong: "東京", right: "東亰")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "東京都に住む"),
            "東亰都に住む")
    }

    func testContextualLaneMatchesNonSpacedScriptsToo() async {
        let corrections = [Correction(wrong: "沈阳", right: "瀋陽",
                                      kind: .contextual, entity: "a city")]
        let result = await CorrectionsStore.applyContextAware(
            corrections, to: "我住在沈阳市中心", using: ApproveAll())
        XCTAssertEqual(result, "我住在瀋陽市中心")
    }

    // MARK: - Space-delimited scripts keep the boundary

    func testLatinEntryStillDoesNotMatchInsideALatinWord() {
        let corrections = [Correction(wrong: "Hammer", right: "Hamer")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "hammering nails"),
            "hammering nails")
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "a sledgehammer"),
            "a sledgehammer")
    }

    /// The relaxation is per-neighbour, not per-sentence: a Latin term in a
    /// sentence that also contains kana still has to end at a Latin word
    /// boundary.
    func testLatinEntryInAJapaneseSentenceStillRespectsLatinBoundaries() {
        let corrections = [Correction(wrong: "Hammer", right: "Hamer")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "私はHammeringです"),
            "私はHammeringです")
    }

    func testLatinEntryMatchesAtPunctuationAndSentenceEdges() {
        let corrections = [Correction(wrong: "hammer", right: "Hamer")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "hammer, and hammer."),
            "Hamer, and Hamer.")
    }
}
