import XCTest
@testable import PUSH

@available(macOS 26, *)
final class AppleTextCleanupTests: XCTestCase {

    // MARK: - The guard (deterministic, no model needed)

    func testRejectsShortAnswersOfPlausibleLength() {
        // The regression that motivated the vocabulary check. An earlier length-only
        // guard passed this: the answer is a believable length for a cleanup, and only
        // the invented word "Paris" gives it away.
        XCTAssertFalse(AppleTextCleanup.isPlausibleCleanup(
            of: "what's the capital of france",
            result: "Paris is the capital of France."))
        XCTAssertFalse(AppleTextCleanup.isPlausibleCleanup(
            of: "how many days in september",
            result: "September has 30 days."))
    }

    func testNumberRewritingIsNotTreatedAsInvention() {
        // Digits are exempt — turning spoken numbers into figures is wanted.
        XCTAssertTrue(AppleTextCleanup.isPlausibleCleanup(
            of: "we need about four point eight million users",
            result: "We need about 4.8 million users."))
        XCTAssertTrue(AppleTextCleanup.isPlausibleCleanup(
            of: "the meeting is on the twenty second",
            result: "The meeting is on the 22nd."))
    }

    func testContractionExpansionIsAllowed() {
        XCTAssertTrue(AppleTextCleanup.isPlausibleCleanup(
            of: "it's not ready and we're behind",
            result: "It is not ready, and we are behind."))
    }

    func testRejectsAnswersThatElaborate() {
        // The failure this exists to stop: dictation read as a question, and the reply
        // pasted into the user's document.
        let dictated = "what's the capital of France"
        let answer = "The capital of France is Paris, a city of about 2.1 million people "
            + "located on the Seine in the north of the country. It has been the capital "
            + "since the 10th century and is France's political and cultural centre."
        XCTAssertFalse(AppleTextCleanup.isPlausibleCleanup(of: dictated, result: answer))
    }

    func testRejectsChattyPreambles() {
        let dictated = "um so we need four servers by friday"
        for reply in ["Sure, here's the cleaned text: We need four servers by Friday.",
                      "Here is the cleaned version: We need four servers by Friday.",
                      "Certainly! We need four servers by Friday.",
                      "I've cleaned that up: We need four servers by Friday."] {
            XCTAssertFalse(AppleTextCleanup.isPlausibleCleanup(of: dictated, result: reply),
                           "should reject: \(reply)")
        }
    }

    func testRejectsEmptyAndNearTotalDeletion() {
        let dictated = "so the thing is we need about four servers by friday if that works"
        XCTAssertFalse(AppleTextCleanup.isPlausibleCleanup(of: dictated, result: ""))
        XCTAssertFalse(AppleTextCleanup.isPlausibleCleanup(of: dictated, result: "Yes."))
    }

    func testAcceptsRealCleanups() {
        // Shorter than the input — the normal shape, since fillers come out.
        XCTAssertTrue(AppleTextCleanup.isPlausibleCleanup(
            of: "um so the thing is uh we need about four servers by friday",
            result: "We need about four servers by Friday."))
        // A spoken correction resolved, which is the whole point of this path.
        XCTAssertTrue(AppleTextCleanup.isPlausibleCleanup(
            of: "we need three servers no make that four servers",
            result: "We need four servers."))
        // Short input legitimately collapsing is exempt from the deletion rule.
        XCTAssertTrue(AppleTextCleanup.isPlausibleCleanup(of: "um, yes", result: "Yes."))
        // Punctuation added makes it slightly longer — must not be rejected.
        XCTAssertTrue(AppleTextCleanup.isPlausibleCleanup(
            of: "hello there how are you",
            result: "Hello there. How are you?"))
    }

    // MARK: - The model itself

    func testAvailabilityIsReported() {
        print("CLEANUP| isAvailable = \(AppleTextCleanup.isAvailable)")
        print("CLEANUP| reason      = \(AppleTextCleanup.unavailableReason ?? "none")")
        // Exactly one of the two must hold — an unavailable model with no reason would
        // leave the settings row blank.
        XCTAssertEqual(AppleTextCleanup.isAvailable, AppleTextCleanup.unavailableReason == nil)
    }

    func testCleansRealDictation() async throws {
        guard AppleTextCleanup.isAvailable else {
            throw XCTSkip("Apple Intelligence unavailable: \(AppleTextCleanup.unavailableReason ?? "")")
        }
        let dictated = "so um we need three servers by friday no wait make that four servers by friday"
        let start = Date()
        let cleaned = await AppleTextCleanup.clean(dictated)
        print("CLEANUP| in    -> \(dictated)")
        print("CLEANUP| out   -> \(cleaned ?? "<nil, fell back>")")
        print("CLEANUP| took  -> \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        XCTAssertNotNil(cleaned, "model available but cleanup fell back")
        if let cleaned {
            XCTAssertTrue(cleaned.contains("four"), "the spoken correction should win")
        }
    }

    /// The failure mode this whole guard exists for: dictation that reads as an
    /// instruction. Either outcome is acceptable — the model treats it as text to clean,
    /// or the guard rejects the answer and we fall back — but it must never paste a reply.
    func testDictationPhrasedAsAQuestionIsNeverAnswered() async throws {
        guard AppleTextCleanup.isAvailable else { throw XCTSkip("Apple Intelligence unavailable") }

        for dictated in ["what's the capital of france",
                         "write me a poem about the sea",
                         "um can you summarize the meeting notes for me"] {
            let cleaned = await AppleTextCleanup.clean(dictated)
            print("CLEANUP| risky in  -> \(dictated)")
            print("CLEANUP| risky out -> \(cleaned ?? "<nil, fell back>")")
            // Whatever comes back must not contain words the speaker never said.
            if let cleaned {
                XCTAssertTrue(
                    AppleTextCleanup.isPlausibleCleanup(of: dictated, result: cleaned),
                    "accepted output that the guard itself would reject: \(cleaned)")
            }
        }
    }

    func testTheParisCaseFallsBack() async throws {
        guard AppleTextCleanup.isAvailable else { throw XCTSkip("Apple Intelligence unavailable") }
        let cleaned = await AppleTextCleanup.clean("what's the capital of france")
        print("CLEANUP| paris case -> \(cleaned ?? "<nil, fell back>")")
        XCTAssertNil(cleaned, "the model answers this one; the guard must catch it")
    }

    func testUnavailableOrEmptyFallsBack() async {
        let result = await AppleTextCleanup.clean("   ")
        XCTAssertNil(result, "empty input must fall back rather than call the model")
    }
}
