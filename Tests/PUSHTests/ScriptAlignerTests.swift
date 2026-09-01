import XCTest
@testable import PUSHCore

/// Tests for teleprompter voice-following: the windowed matcher and the
/// tracking/adrift/lost state machine.
///
/// The aligner takes its clock as a parameter, so every timing behaviour here
/// runs instantly and deterministically — no sleeps, no microphone.
final class ScriptAlignerTests: XCTestCase {

    /// Feeds a script to an aligner one cumulative partial at a time, the way a
    /// streaming engine emits them, and returns the cursor after each.
    private func read(
        _ aligner: inout ScriptAligner,
        words: [String],
        startingAt t0: TimeInterval = 0,
        interval: TimeInterval = 0.4
    ) -> [Double] {
        var partial = ""
        var positions: [Double] = []
        for (i, word) in words.enumerated() {
            partial += (partial.isEmpty ? "" : " ") + word
            let p = aligner.consume(partial: partial, at: t0 + Double(i) * interval)
            positions.append(p.cursor)
        }
        return positions
    }

    // MARK: - Tokenizing

    func testTokenizeKeepsRangesIntoOriginalText() {
        let aligner = ScriptAligner(script: "Hello, world! It's fine.")
        XCTAssertEqual(aligner.tokens.map(\.normalized), ["hello", "world", "its", "fine"])
        // Ranges point at the real characters, punctuation and all.
        XCTAssertEqual(aligner.text(at: 2), "It's")
    }

    func testNumberWordsFoldToDigits() {
        XCTAssertEqual(ScriptAligner.normalize("Twelve"), "12")
        XCTAssertEqual(ScriptAligner.normalize("12"), "12")
    }

    func testEmptyAndPunctuationOnlyScriptsProduceNoTokens() {
        XCTAssertTrue(ScriptAligner(script: "").tokens.isEmpty)
        XCTAssertTrue(ScriptAligner(script: "—  … !!").tokens.isEmpty)
    }

    // MARK: - Similarity

    func testHomophonesMatchViaSoundex() {
        // Edit distance alone rejects all three of these pairs.
        for (a, b) in [("their", "there"), ("to", "two"), ("for", "four")] {
            let ta = ScriptAligner.tokenize(a)[0]
            let tb = ScriptAligner.tokenize(b)[0]
            XCTAssertGreaterThanOrEqual(
                ScriptAligner.similarity(ta, tb), 0.9,
                "\(a)/\(b) should match as homophones"
            )
        }
    }

    func testUnrelatedWordsDoNotMatch() {
        let a = ScriptAligner.tokenize("elephant")[0]
        let b = ScriptAligner.tokenize("bicycle")[0]
        XCTAssertEqual(ScriptAligner.similarity(a, b), 0.0)
    }

    // MARK: - Tracking

    func testCleanReadAdvancesMonotonically() {
        let words = ["the", "quick", "brown", "fox", "jumps", "over", "the",
                     "lazy", "dog", "and", "keeps", "running"]
        var aligner = ScriptAligner(script: words.joined(separator: " "))
        let positions = read(&aligner, words: words)

        XCTAssertEqual(aligner.state, .tracking)
        XCTAssertEqual(zip(positions, positions.dropFirst()).filter { $0 > $1 }.count, 0,
                       "cursor went backwards during a clean read: \(positions)")
        XCTAssertEqual(aligner.cursor, words.count - 1)
    }

    /// The windowing regression test. A phrase that recurs later in the script
    /// must not drag the cursor to the later copy.
    func testRepeatedPhraseDoesNotTeleportCursor() {
        let script = """
        and then we opened the box and inside there was nothing at all so we \
        waited a while and then we opened the box again
        """
        var aligner = ScriptAligner(script: script)
        let firstPass = ["and", "then", "we", "opened", "the", "box"]
        _ = read(&aligner, words: firstPass)

        XCTAssertLessThan(aligner.cursor, 10,
                          "matched the second 'and then we opened the box' instead of the first")
    }

    func testAsrSubstitutionsStillTrack() {
        let script = "there are two roads here and you should take the one on the left"
        var aligner = ScriptAligner(script: script)
        // Homophone slips an engine plausibly makes: there→their, two→to.
        let heard = ["their", "are", "to", "roads", "here", "and", "you", "should", "take"]
        _ = read(&aligner, words: heard)

        XCTAssertEqual(aligner.state, .tracking)
        XCTAssertGreaterThanOrEqual(aligner.cursor, 7,
                                    "lost the thread on homophone substitutions")
    }

    func testSkippedSentenceReacquiresForward() {
        let script = """
        first we check the wiring then we check the pressure valve and the \
        secondary seal after that we run the calibration sweep
        """
        var aligner = ScriptAligner(script: script)
        _ = read(&aligner, words: ["first", "we", "check", "the", "wiring"])
        let before = aligner.cursor

        // Jump forward past a whole clause.
        _ = aligner.consume(partial: "we run the calibration sweep", at: 3.0)

        XCTAssertGreaterThan(aligner.cursor, before + 5, "did not re-acquire after a skip")
        XCTAssertEqual(aligner.state, .tracking)
    }

    // MARK: - Adrift and lost

    func testAdLibGoesAdriftThenSnapsBackOnRejoin() {
        let script = """
        welcome back everyone today we are looking at the new release and the \
        three things that changed in it
        """
        var aligner = ScriptAligner(script: script)
        _ = read(&aligner, words: ["welcome", "back", "everyone", "today"])
        let held = aligner.cursor

        // Off-script for a few seconds. Nothing matches, so nothing moves.
        _ = aligner.consume(partial: "welcome back everyone today oh hang on my coffee", at: 3.0)
        XCTAssertEqual(aligner.cursor, held, "cursor moved while off-script")
        XCTAssertEqual(aligner.state, .adrift)

        // Rejoining mid-sentence snaps onto the right place.
        _ = aligner.consume(partial: "the three things that changed", at: 4.0)
        XCTAssertEqual(aligner.state, .tracking)
        XCTAssertGreaterThan(aligner.cursor, held + 5)
    }

    func testSilenceBecomesLostButHoldsPosition() {
        let words = ["we", "begin", "with", "the", "simplest", "possible", "case",
                     "and", "then", "we", "add", "one", "wrinkle", "at", "a", "time"]
        var aligner = ScriptAligner(script: words.joined(separator: " "))
        _ = read(&aligner, words: Array(words.prefix(8)), interval: 0.4)
        let stopped = aligner.cursor

        // Just past the adrift line: holding.
        XCTAssertEqual(aligner.tick(at: 5.0).state, .adrift)

        // Past the lost line: still holding. A reader who pauses — to think, to
        // skip a line deliberately, to drink — must not have the script walk
        // away from them. Voice-following never invents motion.
        let lost = aligner.tick(at: 9.0)
        XCTAssertEqual(lost.state, .lost)
        XCTAssertEqual(lost.cursor, Double(stopped))
        XCTAssertEqual(aligner.tick(at: 60.0).cursor, Double(stopped))
    }

    func testALongSilenceNeverMovesTheCursor() {
        let words = ["one", "two", "three", "four", "five", "six"]
        var aligner = ScriptAligner(script: words.joined(separator: " "))
        _ = read(&aligner, words: words)
        let reached = aligner.cursor

        XCTAssertEqual(aligner.tick(at: 10_000).cursor, Double(reached))
    }

    func testMeasuredPaceReflectsTheSpeaker() {
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
                     "golf", "hotel", "india", "juliet"]
        var aligner = ScriptAligner(script: words.joined(separator: " "))
        // One token every 0.5s = 120 wpm.
        _ = read(&aligner, words: words, interval: 0.5)

        let wpm = try? XCTUnwrap(aligner.measuredWordsPerMinute)
        XCTAssertNotNil(wpm)
        XCTAssertEqual(wpm ?? 0, 120, accuracy: 20)
    }

    /// A take where the microphone never delivers anything must not look
    /// healthy. Regression for the wiring bug where every partial was posted to
    /// the dictation handler and dropped, leaving the prompter parked at the top
    /// of the script with a green light.
    func testNeverHearingAnythingReportsLostRatherThanIdlingForever() {
        var aligner = ScriptAligner(script: "one two three four five six seven eight")

        // Early on, silence is just a reader who has not started.
        XCTAssertEqual(aligner.tick(at: 0).state, .idle)
        XCTAssertEqual(aligner.tick(at: 2).state, .idle)

        // Past the lost threshold it has to admit it is hearing nothing.
        let lost = aligner.tick(at: 6)
        XCTAssertEqual(lost.state, .lost)

        // But it must not drift: there is no measured pace, and walking the
        // script away from someone who hasn't spoken is worse than holding.
        XCTAssertEqual(lost.cursor, 0)
        XCTAssertEqual(aligner.tick(at: 30).cursor, 0)
    }

    func testAFirstMatchClearsTheNeverHeardAnythingState() {
        var aligner = ScriptAligner(script: "one two three four five six seven eight")
        // The first tick starts the take's clock, as the 20Hz ticker does.
        XCTAssertEqual(aligner.tick(at: 0).state, .idle)
        XCTAssertEqual(aligner.tick(at: 6).state, .lost)

        _ = aligner.consume(partial: "one two three", at: 7)
        XCTAssertEqual(aligner.state, .tracking)
        XCTAssertGreaterThan(aligner.cursor, 0)
    }

    // MARK: - Manual correction

    func testSeekMovesTheCursorAndMatchingResumesFromThere() {
        let words = ["one", "two", "three", "four", "five", "six", "seven",
                     "eight", "nine", "ten", "eleven", "twelve"]
        var aligner = ScriptAligner(script: words.joined(separator: " "))
        _ = read(&aligner, words: ["one", "two", "three"])

        aligner.seek(to: 8, at: 5.0)
        XCTAssertEqual(aligner.cursor, 8)
        XCTAssertEqual(aligner.state, .tracking)

        // Matching continues around the corrected position, not the old one.
        _ = aligner.consume(partial: "ten eleven twelve", at: 5.5)
        XCTAssertGreaterThanOrEqual(aligner.cursor, 10)
    }

    func testSeekClampsAndIgnoresAnEmptyScript() {
        var empty = ScriptAligner(script: "")
        empty.seek(to: 5, at: 0)
        XCTAssertEqual(empty.cursor, -1, "seek on an empty script should do nothing")

        var aligner = ScriptAligner(script: "one two three")
        aligner.seek(to: 99, at: 0)
        XCTAssertEqual(aligner.cursor, 2)
        aligner.seek(to: -7, at: 0)
        XCTAssertEqual(aligner.cursor, 0)
    }

    // MARK: - Degenerate input

    func testStateStartsIdleAndSurvivesEmptyInput() {
        var aligner = ScriptAligner(script: "")
        XCTAssertEqual(aligner.state, .idle)
        XCTAssertEqual(aligner.consume(partial: "anything at all", at: 1.0).state, .idle)
        XCTAssertEqual(aligner.tick(at: 99).cursor, 0)
    }

    func testSingleTokenScript() {
        var aligner = ScriptAligner(script: "Go.")
        let p = aligner.consume(partial: "go", at: 0)
        XCTAssertEqual(p.cursor, 0)
        XCTAssertEqual(aligner.state, .tracking)
    }

    func testCursorAtFinalTokenStaysThere() {
        let words = ["nearly", "at", "the", "very", "end", "now"]
        var aligner = ScriptAligner(script: words.joined(separator: " "))
        _ = read(&aligner, words: words)
        XCTAssertEqual(aligner.cursor, words.count - 1)

        // More speech with nowhere left to go must not crash or overrun.
        _ = aligner.consume(partial: words.joined(separator: " ") + " and beyond", at: 5.0)
        XCTAssertLessThanOrEqual(aligner.cursor, words.count - 1)
    }
}
