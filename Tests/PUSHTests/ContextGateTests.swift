import XCTest
@testable import PUSH
@testable import PUSHCore

/// Tests for the context-aware dictionary: prompt building/parsing, the
/// heuristic gate, and correction application.
final class ContextGateTests: XCTestCase {

    private typealias Correction = CorrectionsStore.Correction

    // MARK: - Prompt parsing (fail-safe by contract)

    func testParseAppliesNumberedVerdicts() {
        let verdicts = ContextGatePrompt.parse("1 APPLY\n2 KEEP\n3 APPLY", count: 3)
        XCTAssertEqual(verdicts, [.apply, .keep, .apply])
    }

    func testParseDefaultsMissingOrGarbledLinesToKeep() {
        XCTAssertEqual(ContextGatePrompt.parse("1 APPLY", count: 3), [.apply, .keep, .keep])
        XCTAssertEqual(ContextGatePrompt.parse("nonsense output", count: 2), [.keep, .keep])
        XCTAssertEqual(ContextGatePrompt.parse("", count: 2), [.keep, .keep])
    }

    func testParseIgnoresOutOfRangeNumbers() {
        XCTAssertEqual(ContextGatePrompt.parse("7 APPLY\n0 APPLY", count: 2), [.keep, .keep])
    }

    func testPromptContainsSentenceAndNumberedCandidates() {
        let prompt = ContextGatePrompt.build(
            sentence: "email Hammer about it",
            candidates: [
                CorrectionCandidate(matchedText: "Hammer", location: 6,
                                    replacement: "Hamer", entity: "a person named Hamer")
            ])
        XCTAssertTrue(prompt.contains("email Hammer about it"))
        XCTAssertTrue(prompt.contains("1. \"Hammer\""))
        XCTAssertTrue(prompt.contains("a person named Hamer"))
    }

    // MARK: - Always lane

    func testAlwaysReplacementIsCaseInsensitiveWholeWord() {
        let corrections = [Correction(wrong: "Hammer", right: "Hamer")]
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "tell hammer hello"),
            "tell Hamer hello")
        // Substrings must not match.
        XCTAssertEqual(
            CorrectionsStore.applyReplacements(corrections, to: "hammering nails"),
            "hammering nails")
    }

    // MARK: - Contextual lane (heuristic gate end-to-end)

    func testContextualAppliesAfterEntityTrigger() async {
        let corrections = [Correction(wrong: "Hammer", right: "Hamer",
                                      kind: .contextual, entity: "a person named Hamer")]
        let result = await CorrectionsStore.applyContextAware(
            corrections, to: "send an email to Hammer today")
        XCTAssertEqual(result, "send an email to Hamer today")
    }

    func testContextualKeepsOrdinaryWord() async {
        let corrections = [Correction(wrong: "hammer", right: "Hamer",
                                      kind: .contextual, entity: "a person named Hamer")]
        let result = await CorrectionsStore.applyContextAware(
            corrections, to: "I need a hammer for this nail")
        XCTAssertEqual(result, "I need a hammer for this nail")
    }

    func testContextualAppliesForCapitalizedMidSentenceName() async {
        let corrections = [Correction(wrong: "Hammer", right: "Hamer",
                                      kind: .contextual, entity: "a person named Hamer")]
        let result = await CorrectionsStore.applyContextAware(
            corrections, to: "We saw Hammer yesterday")
        XCTAssertEqual(result, "We saw Hamer yesterday")
    }

    func testContextualKeepsSentenceInitialCapital() async {
        // Sentence-initial capitalization proves nothing — fail-safe keeps it.
        let corrections = [Correction(wrong: "Hammer", right: "Hamer",
                                      kind: .contextual, entity: "a person named Hamer")]
        let result = await CorrectionsStore.applyContextAware(
            corrections, to: "Hammer is a useful tool")
        XCTAssertEqual(result, "Hammer is a useful tool")
    }

    func testMixedLanesApplyIndependently() async {
        let corrections = [
            Correction(wrong: "acme", right: "ACME"),
            Correction(wrong: "hammer", right: "Hamer",
                       kind: .contextual, entity: "a person named Hamer")
        ]
        let result = await CorrectionsStore.applyContextAware(
            corrections, to: "acme sells a hammer")
        XCTAssertEqual(result, "ACME sells a hammer")
    }

    // MARK: - Engine routing guard

    func testWhisperEngineRejectsNonWhisperKitModels() async {
        // Regression guard for the wake word bug: loading a Moonshine/Parakeet
        // model through WhisperEngine must throw, not attempt an empty download.
        do {
            try await WhisperEngine.shared.loadModel(.parakeetV2)
            XCTFail("Expected loadModel to throw for a non-WhisperKit model")
        } catch {
            XCTAssertTrue(error is WhisperError)
        }
    }
}
