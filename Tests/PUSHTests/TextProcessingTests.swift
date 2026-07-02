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
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("I think, um, it works"), "I think, it works")
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("it was uh really good"), "it was really good")
    }

    func testLikeOnlyRemovedWhenCommaBounded() {
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("I like pizza"), "I like pizza")
        XCTAssertEqual(TranscriptionPipeline.removeFillerWords("I was, like, going"), "I was, going")
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
}
