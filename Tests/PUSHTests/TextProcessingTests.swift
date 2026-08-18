import XCTest
@testable import PUSH

/// Tests for the pure text post-processing functions in TranscriptionPipeline.
final class TextProcessingTests: XCTestCase {

    // MARK: - Number words (AP style)

    func testNumbersTenAndAboveBecomeDigits() {
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("twenty-five years"), "25 years")
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("I waited ten minutes"), "I waited 10 minutes")
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("one hundred five"), "105")
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("two thousand twenty four"), "2024")
    }

    func testNumbersUnderTenStaySpelled() {
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("five apples"), "five apples")
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("one of them"), "one of them")
    }

    func testExistingDigitsUntouched() {
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("I have 42 things"), "I have 42 things")
    }

    // MARK: - Thousands grouping

    func testGroupThousandsAddsCommasToLargeNumbers() {
        XCTAssertEqual(TranscriptionPipeline.groupThousands("30000000"), "30,000,000")
        XCTAssertEqual(TranscriptionPipeline.groupThousands("I owe 12345 dollars"), "I owe 12,345 dollars")
        XCTAssertEqual(TranscriptionPipeline.groupThousands("10000 and 250000"), "10,000 and 250,000")
    }

    func testGroupThousandsLeavesFourDigitNumbersAlone() {
        // Years and other 4-digit values are ambiguous — don't group them.
        XCTAssertEqual(TranscriptionPipeline.groupThousands("in 2024 we shipped"), "in 2024 we shipped")
        XCTAssertEqual(TranscriptionPipeline.groupThousands("port 8080"), "port 8080")
    }

    func testGroupThousandsLeavesDecimalsAndVersionsAlone() {
        // Fractional digits must never be grouped.
        XCTAssertEqual(TranscriptionPipeline.groupThousands("pi is 3.141592"), "pi is 3.141592")
        XCTAssertEqual(TranscriptionPipeline.groupThousands("version 4.0.2"), "version 4.0.2")
        // But a large integer part before a decimal still groups.
        XCTAssertEqual(TranscriptionPipeline.groupThousands("12345.67"), "12,345.67")
    }

    func testGroupThousandsLeavesAlreadyGroupedNumbersAlone() {
        XCTAssertEqual(TranscriptionPipeline.groupThousands("30,000,000"), "30,000,000")
    }

    func testSpokenLargeNumbersEndUpGrouped() {
        // The full path the bug report hits: "thirty million" → digits → commas.
        let digits = TranscriptionPipeline.normalizeNumberWords("thirty million")
        XCTAssertEqual(TranscriptionPipeline.groupThousands(digits), "30,000,000")
    }

    func testStripConnectingAnd() {
        XCTAssertEqual(
            TranscriptionPipeline.normalizeNumberWords(
                TranscriptionPipeline.stripConnectingAnd("one hundred and forty two people")),
            "142 people")
        // "and" between standalone numbers is a real conjunction — keep it.
        XCTAssertEqual(TranscriptionPipeline.stripConnectingAnd("five and ten"), "five and ten")
    }

    // MARK: - Decimal dictation

    func testDecimalDictation() {
        XCTAssertEqual(TranscriptionPipeline.normalizeDecimalDictation("ten point five"), "10.5")
        XCTAssertEqual(TranscriptionPipeline.normalizeDecimalDictation("four point zero point two"), "4.0.2")
        XCTAssertEqual(TranscriptionPipeline.normalizeDecimalDictation("version five point oh"), "version 5.0")
    }

    func testDecimalDictationLeavesPlainPointAlone() {
        XCTAssertEqual(
            TranscriptionPipeline.normalizeDecimalDictation("that is my point exactly"),
            "that is my point exactly")
    }

    // MARK: - Ordinals

    func testOrdinals() {
        XCTAssertEqual(TranscriptionPipeline.normalizeOrdinals("March fifth"), "March 5th")
        XCTAssertEqual(TranscriptionPipeline.normalizeOrdinals("twenty fifth"), "25th")
        XCTAssertEqual(TranscriptionPipeline.normalizeOrdinals("the twenty second of May"), "the 22nd of May")
        XCTAssertEqual(TranscriptionPipeline.normalizeOrdinals("thirty first"), "31st")
    }

    func testBareFirstAndSecondAreNotConverted() {
        XCTAssertEqual(TranscriptionPipeline.normalizeOrdinals("first of all"), "first of all")
        XCTAssertEqual(TranscriptionPipeline.normalizeOrdinals("wait a second"), "wait a second")
    }

    // MARK: - Fillers & stutters

    func testRemoveFillerWords() {
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("Um, I think so"), "I think so")
        // The commas bracketed the filler, so they leave with it. This used to
        // assert "I think, it works" — the filler gone and a comma splice left
        // behind in its place.
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("I think, um, it works"), "I think it works")
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("it was uh really good"), "it was really good")
    }

    func testLikeAsAVerbIsNeverRemoved() {
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("I like pizza"), "I like pizza")
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("I was, like, going"), "I was going")
    }

    func testRemoveStutteredWords() {
        XCTAssertEqual(TranscriptionPipeline.removeStutteredWords("the the cat"), "the cat")
        XCTAssertEqual(TranscriptionPipeline.removeStutteredWords("I I think"), "I think")
        XCTAssertEqual(TranscriptionPipeline.removeStutteredWords("no repeats here"), "no repeats here")
    }

    // MARK: - Punctuation & capitalization

    func testFixQuestionMarks() {
        XCTAssertEqual(TranscriptionPipeline.fixQuestionMarks("what time is it."), "what time is it?")
        XCTAssertEqual(TranscriptionPipeline.fixQuestionMarks("I know what it is."), "I know what it is.")
        XCTAssertEqual(
            TranscriptionPipeline.fixQuestionMarks("can you help. thanks."),
            "can you help? thanks.")
    }

    func testFixCapitalization() {
        XCTAssertEqual(TranscriptionPipeline.fixCapitalization("hello. world"), "Hello. World")
        XCTAssertEqual(TranscriptionPipeline.fixCapitalization("one? two! three."), "One? Two! Three.")
    }

    func testCapitalizeI() {
        XCTAssertEqual(TranscriptionPipeline.capitalizeI("i think i can"), "I think I can")
        XCTAssertEqual(TranscriptionPipeline.capitalizeI("it is inside"), "it is inside")
    }

    func testEnsureEndingPunctuation() {
        XCTAssertEqual(TranscriptionPipeline.ensureEndingPunctuation("hello"), "hello.")
        XCTAssertEqual(TranscriptionPipeline.ensureEndingPunctuation("hello!"), "hello!")
        XCTAssertEqual(TranscriptionPipeline.ensureEndingPunctuation("really?"), "really?")
    }

    func testFixTrailingComma() {
        XCTAssertEqual(TranscriptionPipeline.fixTrailingComma("see you soon,"), "see you soon.")
        XCTAssertEqual(TranscriptionPipeline.fixTrailingComma("see you soon."), "see you soon.")
    }

    func testDoubleSpaceAfterPeriods() {
        XCTAssertEqual(TranscriptionPipeline.doubleSpaceAfterPeriods("Hi. There"), "Hi.  There")
        // Already double-spaced input must not grow further.
        XCTAssertEqual(TranscriptionPipeline.doubleSpaceAfterPeriods("Hi.  There"), "Hi.  There")
    }

    // MARK: - Symbols & contractions

    func testSmartSymbols() {
        XCTAssertEqual(TranscriptionPipeline.smartSymbols("50 percent done"), "50% done")
        XCTAssertEqual(TranscriptionPipeline.smartSymbols("it costs 100 dollars"), "it costs $100")
        XCTAssertEqual(TranscriptionPipeline.smartSymbols("use the at sign here"), "use the @ here")
        XCTAssertEqual(TranscriptionPipeline.smartSymbols("add a hashtag please"), "add a # please")
    }

    func testNormalizeCause() {
        XCTAssertEqual(TranscriptionPipeline.normalizeCause("'cause I said so"), "cause I said so")
        XCTAssertEqual(TranscriptionPipeline.normalizeCause("just \u{2019}cause"), "just cause")
        // A real possessive/word containing "cause" is left alone.
        XCTAssertEqual(TranscriptionPipeline.normalizeCause("the cause of it"), "the cause of it")
    }

    // MARK: - Filler "like"

    private func filler(_ text: String) -> String {
        TranscriptionPipeline.removeFillerWords(text)
    }

    func testFillerLikeIsRemoved() {
        XCTAssertEqual(filler("I was, like, going"), "I was going")
        XCTAssertEqual(filler("it works for like normal situations"),
                       "it works for normal situations")
        XCTAssertEqual(filler("Like, I don't know"), "I don't know")
        XCTAssertEqual(filler("Fine. Like, whatever"), "Fine. whatever")
    }

    /// Real dictation. Both of these survived the first implementation, which
    /// only knew about prepositions and sentence starts.
    func testFillerLikeAfterNegationAndPronoun() {
        XCTAssertEqual(
            filler("How are you not like irate about Bill's emails as if he like lives on another planet"),
            "How are you not irate about Bill's emails as if he lives on another planet"
        )
        XCTAssertEqual(filler("and like nobody cared"), "and nobody cared")
        XCTAssertEqual(filler("it's like really cold"), "it's really cold")
    }

    /// The catastrophic case. A rule matching pronoun + "like" without checking
    /// the part of speech turns this into "I pizza".
    func testLikeAsMainVerbAfterPronounIsNeverRemoved() {
        XCTAssertEqual(filler("I like pizza"), "I like pizza")
        XCTAssertEqual(filler("they like us"), "they like us")
        XCTAssertEqual(filler("we like it here"), "we like it here")
    }

    /// "like" is a verb, a comparison and an approximation as well as a filler.
    /// Each of these changes meaning if it is stripped.
    func testMeaningfulLikeSurvives() {
        XCTAssertEqual(filler("I like it"), "I like it")
        XCTAssertEqual(filler("it looks like rain"), "it looks like rain")
        XCTAssertEqual(filler("do it like this"), "do it like this")
        XCTAssertEqual(filler("it was like a dream"), "it was like a dream")
        XCTAssertEqual(filler("I would like a coffee"), "I would like a coffee")
        XCTAssertEqual(filler("people like us"), "people like us")
    }

    /// "in like 30 minutes" means about thirty. Dropping the "like" would turn
    /// an approximation into a precise claim.
    func testApproximationLikeSurvives() {
        XCTAssertEqual(filler("I'll be there in like 30 minutes"),
                       "I'll be there in like 30 minutes")
        XCTAssertEqual(filler("it costs about like 20 dollars"),
                       "it costs about like 20 dollars")
    }

    // MARK: - Spoken self-corrections

    private func resolve(_ text: String) -> String {
        TranscriptionPipeline.resolveSelfCorrections(text)
    }

    func testReplacementDropsTheCorrectedSpan() {
        XCTAssertEqual(resolve("I want the red car, I mean the blue car"),
                       "I want the blue car")
        XCTAssertEqual(resolve("meet me at four, I meant at five"),
                       "meet me at five")
        XCTAssertEqual(resolve("send it to Dave, no wait to Sarah"),
                       "send it to Sarah")
    }

    func testRestartDropsTheWholeClause() {
        XCTAssertEqual(resolve("let's go to the park, scratch that let's stay home"),
                       "let's stay home")
        XCTAssertEqual(resolve("the total is fifty, delete that the total is sixty"),
                       "the total is sixty")
    }

    /// The most important property here: a correction must never eat the
    /// sentence before it, however the word count lands.
    func testDeletionStopsAtTheSentenceBoundary() {
        XCTAssertEqual(resolve("Keep this sentence. Red, I mean blue"),
                       "Keep this sentence. blue")
        XCTAssertEqual(resolve("First thought. Second one, scratch that third one"),
                       "First thought. third one")
    }

    /// False positives silently delete what the user said, so the ambiguous
    /// markers are deliberately not recognised. These must pass through whole.
    func testAmbiguousMarkersAreLeftAlone() {
        XCTAssertEqual(resolve("I'm sorry about the delay"),
                       "I'm sorry about the delay")
        XCTAssertEqual(resolve("I actually like the red one"),
                       "I actually like the red one")
        XCTAssertEqual(resolve("I'd rather go tomorrow"),
                       "I'd rather go tomorrow")
    }

    func testOrdinaryTextIsUntouched() {
        XCTAssertEqual(resolve("The quick brown fox jumps over the lazy dog"),
                       "The quick brown fox jumps over the lazy dog")
        XCTAssertEqual(resolve(""), "")
    }

    /// Word-boundary check: a marker embedded in a longer word must not fire.
    func testMarkerInsideAWordDoesNotFire() {
        XCTAssertEqual(resolve("in the meantime we wait"), "in the meantime we wait")
    }

    func testDanglingMarkerWithNothingAfterItIsDropped() {
        XCTAssertEqual(resolve("the red car, I mean"), "the red car")
    }

    func testMultipleCorrectionsResolveInOrder() {
        XCTAssertEqual(resolve("call Bob, I mean call Sue, I mean call Ann"),
                       "call Ann")
    }
}
