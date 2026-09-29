import XCTest
@testable import PUSH
@testable import PUSHCore

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

    // MARK: - Clock times

    /// The Parakeet models write spoken times as "3.30" or "3 30". Real
    /// dictations, verbatim from Ultra and Unified.
    func testDottedAndSpacedClockTimesGetAColon() {
        let t = TranscriptionPipeline.normalizeClockTimes
        XCTAssertEqual(t("3 30 p.m. 3 30 on a Friday."), "3:30 p.m. 3:30 on a Friday.")
        XCTAssertEqual(t("Let's meet at 3.30 on Friday."), "Let's meet at 3:30 on Friday.")
        XCTAssertEqual(t("The call is at 10.15 tomorrow."), "The call is at 10:15 tomorrow.")
        XCTAssertEqual(t("Pick me up at 7.45pm."), "Pick me up at 7:45pm.")
        XCTAssertEqual(t("It's 3.30 pm on a Friday."), "It's 3:30 pm on a Friday.")
        XCTAssertEqual(t("maybe by 12.30"), "maybe by 12:30")
        XCTAssertEqual(t("from 9 00 until 5 30"), "from 9:00 until 5:30")
        XCTAssertEqual(t("at three 30"), "at 3:30")
        XCTAssertEqual(t("The show starts at 8.15 this evening."), "The show starts at 8:15 this evening.")
    }

    /// The same shapes are prices, versions and plain numbers. With no clock
    /// cue beside them they must come through untouched.
    func testNumbersThatAreNotTimesAreLeftAlone() {
        let t = TranscriptionPipeline.normalizeClockTimes
        XCTAssertEqual(t("The coffee costs 3.30."), "The coffee costs 3.30.")
        XCTAssertEqual(t("It was $3.30 at the store."), "It was $3.30 at the store.")
        XCTAssertEqual(t("We moved from version 2.1."), "We moved from version 2.1.")
        XCTAssertEqual(t("Pi is about 3.14159."), "Pi is about 3.14159.")
        XCTAssertEqual(t("I ran 5.25 miles."), "I ran 5.25 miles.")
        XCTAssertEqual(t("Already written as 3:30 pm."), "Already written as 3:30 pm.")
        XCTAssertEqual(t("I need 3 30-minute slots."), "I need 3 30-minute slots.")
        XCTAssertEqual(t("Grab 2 20 packs at the store."), "Grab 2 20 packs at the store.")
    }

    /// Through the whole English chain, so an earlier pass can't undo it.
    func testClockTimesSurviveTheFullChain() {
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("Let's meet at 3.30 on Friday.", hasNativePunctuation: true),
            "Let's meet at 3:30 on Friday.")
    }

    // MARK: - Spoken quotes

    func testQuoteEndQuoteBecomesQuotationMarks() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        XCTAssertEqual(q("He said quote I'll be there end quote and left."),
                       "He said \"I'll be there\" and left.")
        // The shape the model actually writes: markers wrapped in commas.
        XCTAssertEqual(q("He said, quote, I'll be there, end quote, and left."),
                       "He said, \"I'll be there,\" and left.")
        XCTAssertEqual(q("She told me quote not today unquote."),
                       "She told me \"not today.\"")
        XCTAssertEqual(q("Open quote hello world close quote is the classic."),
                       "\"Hello world\" is the classic.")
        XCTAssertEqual(q("It says quote do not enter. End quote."),
                       "It says \"do not enter.\"")
        XCTAssertEqual(q("Quote one end quote and quote two end quote."),
                       "\"One\" and \"two.\"")
    }

    func testAndIQuoteKeepsItsWordsAndClosesAtTheSentenceEnd() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        XCTAssertEqual(q("He said, and I quote, we're done here."),
                       "He said, and I quote, \"we're done here.\"")
        XCTAssertEqual(q("He said and I quote we're done here. Then he left."),
                       "He said and I quote, \"we're done here.\" Then he left.")
        XCTAssertEqual(q("And I quote, blah blah, end quote, which was rude."),
                       "And I quote, \"blah blah,\" which was rude.")
        XCTAssertEqual(q("The sign said open quote closed for lunch"),
                       "The sign said \"closed for lunch\"")
    }

    /// Periods and commas go inside the closing quote; a question or
    /// exclamation mark belonging to the whole sentence stays outside.
    func testClosingPunctuationFollowsAmericanStyle() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        XCTAssertEqual(q("Did he really say quote yes end quote?"), "Did he really say \"yes\"?")
        XCTAssertEqual(q("Stop saying quote whatever end quote!"), "Stop saying \"whatever\"!")
        XCTAssertEqual(q("She said quote fine end quote, then left."), "She said \"fine,\" then left.")
        XCTAssertEqual(q("He asked, quote, are we done? End quote."), "He asked, \"are we done?\"")
        XCTAssertEqual(q("He asked, and I quote, are we done?"), "He asked, and I quote, \"are we done?\"")
    }

    /// "p.m." and "Dr." are not sentence ends, so a quote runs through them.
    func testAbbreviationsDoNotEndAQuote() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        XCTAssertEqual(q("He told me, quote, we're shipping at 3:30 p.m. tomorrow, end quote, so plan for that."),
                       "He told me, \"we're shipping at 3:30 p.m. tomorrow,\" so plan for that.")
        XCTAssertEqual(q("She said and I quote see Dr. Lee at 9 a.m. sharp. Then she left."),
                       "She said and I quote, \"see Dr. Lee at 9 a.m. sharp.\" Then she left.")
    }

    /// Real dictations, verbatim from Ultra on 8.0.6. Most people never say
    /// "end quote", so a "quote" that plainly opens a quotation closes itself.
    func testQuoteClosesItselfWhereAQuotationPlainlyStarts() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        XCTAssertEqual(q("Quote alliance is here."), "\"Alliance is here.\"")
        XCTAssertEqual(q("Elias said quote let's go home."), "Elias said \"let's go home.\"")
        XCTAssertEqual(q("He said, quote, let's go home. Then we left."),
                       "He said, \"let's go home.\" Then we left.")
        XCTAssertEqual(q("She told me quote not now, maybe later."), "She told me \"not now, maybe later.\"")
    }

    /// With an end marker the quote may span sentences — and a "quote" after
    /// "a" is fine, because the marker settles what was meant.
    func testPairedQuotesSpanSentencesAndResolveAmbiguity() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        XCTAssertEqual(q("Quote Elias is here. Elias is here, end quote."),
                       "\"Elias is here. Elias is here.\"")
        XCTAssertEqual(q("I think it's a quote big deal end quote."), "I think it's a \"big deal.\"")
    }

    /// "quote unquote" said together: scare quotes around what follows.
    func testQuoteUnquoteIdiom() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        XCTAssertEqual(q("It's a quote unquote big deal."), "It's a \"big deal.\"")
        XCTAssertEqual(q("He's a quote-end quote expert on this topic."), "He's a \"expert\" on this topic.")
        XCTAssertEqual(q("That was, quote, end quote, fun, I guess."), "That was, \"fun,\" I guess.")
        // With a quote already open, the idiom closes it.
        XCTAssertEqual(q("Quote, that seems to be pretty good quote-end quote."),
                       "\"That seems to be pretty good.\"")
    }

    /// Real dictation: "…pretty well, quote, end quote." quoted the words
    /// "end quote" themselves. Said after the phrase, it is left as dictated.
    func testMarkersWithNothingAfterThemAreNeverQuoted() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        for s in ["It seems to be working pretty well, quote, end quote.",
                  "That seems to be pretty good quote-end quote.",
                  "That seems pretty good, quote unquote."] {
            XCTAssertEqual(q(s), s)
        }
    }

    /// Where "quote" is the ordinary word it stays, even with the looser rule.
    func testLoneQuoteMidSentenceStaysTheOrdinaryWord() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        for s in ["I think it's a quote big deal.",
                  "How about this quote Elias says here?",
                  "Can you send me a quote for the roof?",
                  "She said, quote me on that.",
                  "His best quote is still the one about luck."] {
            XCTAssertEqual(q(s), s)
        }
    }

    /// A quote never swallows another. Real dictation: "and I quote" opened one
    /// sentence and an "end quote" after another "quote" swallowed both.
    func testAQuoteDoesNotSpanSentences() {
        XCTAssertEqual(
            TranscriptionPipeline.normalizeSpokenQuotes(
                "How hard would it be to say, and I quote blah blah. And then it would put whatever follows."),
            "How hard would it be to say, and I quote, \"blah blah.\" And then it would put whatever follows.")
    }

    /// "quote" is also an ordinary noun and verb. With no end marker, it stays.
    func testOrdinaryUsesOfQuoteAreLeftAlone() {
        let q = TranscriptionPipeline.normalizeSpokenQuotes
        for s in ["Can you get a quote from the contractor?",
                  "That's my favorite quote.",
                  "Please quote me on that.",
                  "The quote was too high, so we passed."] {
            XCTAssertEqual(q(s), s)
        }
    }

    func testSpokenQuotesSurviveTheFullChain() {
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("He said, quote, I'll be there at 3.30, end quote.",
                                              hasNativePunctuation: true),
            "He said, \"I'll be there at 3:30.\"")
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

    func testMagnitudeWordAfterDigitsStaysSpelled() {
        // Bug: "4.8 million" came out as "4.8 1,000,000" — the bare "million"
        // was expanded with an implicit multiplier of 1, losing the 4.8 entirely.
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("that's only like 4.8 million"),
                       "that's only like 4.8 million")
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("30 million"), "30 million")
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("$5 million in revenue"),
                       "$5 million in revenue")
    }

    func testBareMagnitudeWordInProseStaysSpelled() {
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("a hundred people"), "a hundred people")
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("a thousand times"), "a thousand times")
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("a hundred thousand dollars"),
                       "a hundred thousand dollars")
        // A magnitude with a real multiplier still expands.
        XCTAssertEqual(TranscriptionPipeline.normalizeNumberWords("two hundred thousand"), "200,000")
    }

    // MARK: - Composed pipeline
    //
    // These run the whole chain. Every bug below was an *interaction* between
    // passes that each looked correct on its own, so testing them in isolation
    // is what let the bugs ship.

    /// Parakeet's variant — it punctuates natively, so those passes are skipped.
    private func push(_ text: String) -> String {
        TranscriptionPipeline.postProcess(text, hasNativePunctuation: true)
    }

    func testDecimalKeepsItsMagnitudeWord() {
        // Was "4.8000000": the fractional chunk swallowed "million" and summed it.
        XCTAssertEqual(push("four point eight million"), "4.8 million")
        XCTAssertEqual(push("4.8 million"), "4.8 million")
        // The integer side may still carry a magnitude.
        XCTAssertEqual(push("one hundred point five"), "100.5")
    }

    func testDictatedDigitsAfterThePointConcatenate() {
        // Was "3.5" — the run "one four" was summed instead of read off as digits.
        XCTAssertEqual(push("three point one four"), "3.14")
        XCTAssertEqual(push("three point one four one five nine"), "3.14159")
        // A run that isn't all single digits is still arithmetic.
        XCTAssertEqual(push("ten point twenty five"), "10.25")
        XCTAssertEqual(push("ten point five"), "10.5")
        XCTAssertEqual(push("version five point oh"), "version 5.0")
    }

    func testDollarAmountsTakeTheWholeNumber() {
        // Was "5,000,$000": the dollar rule runs after comma-grouping and a bare
        // \d+ matched only the final group.
        XCTAssertEqual(push("five million dollars"), "$5,000,000")
        XCTAssertEqual(push("twelve thousand dollars"), "$12,000")
        XCTAssertEqual(push("one hundred thousand dollars"), "$100,000")
        // A trailing magnitude word belongs to the amount.
        XCTAssertEqual(push("5 million dollars"), "$5 million")
        XCTAssertEqual(push("two point five million dollars"), "$2.5 million")
        XCTAssertEqual(push("25 dollars"), "$25")
    }

    func testSpokenThousandsAreGroupedButSpokenYearsAreNot() {
        // Was "1000 people" — groupThousands can't tell a count from a year, but
        // a number that arrived as words carries that provenance.
        XCTAssertEqual(push("one thousand people"), "1,000 people")
        XCTAssertEqual(push("three thousand two hundred"), "3,200")
        XCTAssertEqual(push("two thousand twenty four"), "2024")
        XCTAssertEqual(push("in two thousand twenty four we shipped"), "in 2024 we shipped")
        // Digits the recogniser wrote are still left alone below five figures.
        XCTAssertEqual(push("port 8080"), "port 8080")
    }

    func testTheReportedSentence() {
        XCTAssertEqual(push("that's only like 4.8 million"), "that's only like 4.8 million")
    }

    /// Whisper/Moonshine's variant — they don't punctuate, so those passes run.
    private func whisper(_ text: String) -> String {
        TranscriptionPipeline.postProcess(text, hasNativePunctuation: false)
    }

    func testCapitalizationDoesNotSlideAcrossDigits() {
        // fixCapitalization cleared its flag only on letters, so a pending
        // sentence start survived digits and symbols and landed on the next
        // letter it found.
        XCTAssertEqual(whisper("thirty first"), "31st.")
        XCTAssertEqual(whisper("one hundred and forty two people"), "142 people.")
        XCTAssertEqual(whisper("50 percent off"), "50% off.")
        // The decimal point re-armed the flag: "$2.5 Million".
        XCTAssertEqual(whisper("two point five million dollars"), "$2.5 million.")
        // Real sentence starts still capitalise.
        XCTAssertEqual(whisper("hello. world is here"), "Hello. World is here.")
    }

    func testSpokenYearsReadAsPairs() {
        XCTAssertEqual(TranscriptionPipeline.parseSpokenYear("nineteen ninety nine"), 1999)
        XCTAssertEqual(TranscriptionPipeline.parseSpokenYear("seventeen seventy six"), 1776)
        XCTAssertEqual(whisper("nineteen ninety nine"), "1999.")
        // Ordinary compounds never split — 5 is added to 20, not paired with it.
        XCTAssertNil(TranscriptionPipeline.parseSpokenYear("twenty five"))
        // Out of year range, so a "sixty forty split" doesn't become 6040.
        XCTAssertNil(TranscriptionPipeline.parseSpokenYear("sixty forty"))
        // Magnitude words disqualify the run; this path already worked.
        XCTAssertNil(TranscriptionPipeline.parseSpokenYear("two thousand twenty four"))
        XCTAssertEqual(whisper("in two thousand twenty four we shipped"), "In 2024 we shipped.")
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
        XCTAssertEqual(resolve("the total is fifty, delete that, the total is sixty"),
                       "the total is sixty")
    }

    /// The most important property here: a correction must never eat the
    /// sentence before it, however the word count lands.
    func testDeletionStopsAtTheSentenceBoundary() {
        XCTAssertEqual(resolve("Keep this sentence. Red, I mean blue"),
                       "Keep this sentence. Blue")
        XCTAssertEqual(resolve("First thought. Second one, scratch that third one"),
                       "First thought. Third one")
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

    /// A decimal point is not a sentence end.
    ///
    /// Found by the fixed benchmark script (2026-09-29), which says "15.2
    /// seconds, I mean 1.52 seconds" out loud. Parakeet writes both as digits
    /// and puts a sentence break before the marker, so every dot-scanning pass
    /// saw "1.52" as the end of a sentence after "1": the correction became the
    /// single word "1", and the sentence it was correcting was rebuilt from the
    /// dot inside "15.2". `resolveTrailing` had the rule; nothing else did.
    func testDecimalsAreNotSentenceBoundaries() {
        XCTAssertEqual(
            resolve("Latency came back at 15.2 seconds. I mean 1.52 seconds. So ask the Zurich team to rerun it."),
            "Latency came back at 1.52 seconds. So ask the Zurich team to rerun it.")
        XCTAssertEqual(
            resolve("Latency was 15.2 seconds, I mean 1.52 seconds, so rerun it"),
            "Latency was 1.52 seconds, so rerun it")
    }

    /// The thousands separator is the same trap with a comma.
    func testGroupedNumbersAreNotClauseBoundaries() {
        XCTAssertEqual(resolve("It costs 1,500, I mean 2,500"),
                       "It costs 2,500")
    }

    func testDanglingMarkerWithNothingAfterItIsDropped() {
        XCTAssertEqual(resolve("the red car, I mean"), "the red car")
    }

    /// Real dictation: "I mean, Ultra's been great…" came out as ", Ultra's
    /// been great…". Opening a sentence, a marker corrects nothing and stays.
    func testMarkerOpeningASentenceIsKept() {
        XCTAssertEqual(resolve("I mean, Ultra's been great, to be honest."),
                       "I mean, Ultra's been great, to be honest.")
        XCTAssertEqual(resolve("It works. No wait, it's even better than that."),
                       "It works. No wait, it's even better than that.")
        // A later marker in the same text still resolves.
        XCTAssertEqual(resolve("I mean, it's fine. The red car, I mean the blue car."),
                       "I mean, it's fine. The blue car.")
    }

    /// The comma after a marker goes with it, and a correction that now opens
    /// the text is capitalised.
    func testMarkerCommaIsRemovedWithTheMarker() {
        XCTAssertEqual(resolve("The red car, I mean, the blue car."), "The blue car.")
        XCTAssertEqual(resolve("Let's go out, scratch that, let's stay home."), "Let's stay home.")
    }

    /// "sorry" and "correction" between the slip and the fix.
    func testSorryAndCorrectionBetweenTheSlipAndTheFix() {
        XCTAssertEqual(resolve("Meet at 4, sorry, 5."), "Meet at 5.")
        XCTAssertEqual(resolve("Send it to Dave, sorry, Sarah."), "Send it to Sarah.")
        XCTAssertEqual(resolve("It costs 20, correction, 25 dollars."), "It costs 25 dollars.")
    }

    /// The trailing form, from real dictation: the fix comes first, then
    /// "sorry" — only when a number replaces a number, a day a day.
    func testTrailingSorryReplacesTheSameKindOfWord() {
        XCTAssertEqual(resolve("I'm gonna clean up all things before 7.0. 8.0, sorry."),
                       "I'm gonna clean up all things before 8.0.")
        XCTAssertEqual(resolve("The meeting is Tuesday. Wednesday, sorry."), "The meeting is Wednesday.")
        XCTAssertEqual(resolve("See you at 4, 5, sorry."), "See you at 5.")
    }

    /// Everyday "sorry", "delete that", "start over" and "I mean" pass through.
    func testEverydayUsesOfTheMarkersAreLeftAlone() {
        for s in ["Thanks for waiting, sorry.",
                  "I'm sorry about the delay.",
                  "Sorry, I'm running late.",
                  "The delay was long, sorry, but we'll be there.",
                  "You should delete that file.",
                  "We need to start over with a new plan.",
                  "What I mean is that it works.",
                  "It works, I mean it really does feel faster than the old one, honestly."] {
            XCTAssertEqual(resolve(s), s)
        }
    }

    /// Real dictation, 2026-09-27: talking *about* the markers lost 61 of 114
    /// characters. Listing them, or a long run after one, is not a correction.
    func testListingTheMarkersOrALongRunIsNotACorrection() {
        let s = "I think common words are sorry, correction, I mean, actually I noticed something odd, which I think was part of the last fix."
        XCTAssertEqual(resolve(s), s)
    }

    /// Real dictation on 8.1.0: the model ends the sentence before the fix.
    func testAShortFixReachesBackIntoThePreviousSentence() {
        XCTAssertEqual(resolve("Can you please send a letter to Sarah? I mean John."),
                       "Can you please send a letter to John?")
        XCTAssertEqual(resolve("Can you please send a letter to Sarah? Sorry, John."),
                       "Can you please send a letter to John?")
        XCTAssertEqual(resolve("It'll be tomorrow at eight o'clock. I mean four o'clock."),
                       "It'll be tomorrow at four o'clock.")
        XCTAssertEqual(resolve("I'll bring the red one. Sorry, the blue one. See you there."),
                       "I'll bring the blue one. See you there.")
    }

    /// Reaching back needs a visible correspondence; otherwise the new
    /// sentence is just speech and stays.
    func testReachingBackNeedsTheFixToLineUp() {
        for s in ["I love it. I mean it.",
                  "It's great. I mean, it really works.",
                  "Sorry, I'm running late.",
                  "The meeting is at noon. Sorry, I have to go.",
                  "We saw Paris. I mean, wow."] {
            XCTAssertEqual(resolve(s), s)
        }
    }

    func testMultipleCorrectionsResolveInOrder() {
        XCTAssertEqual(resolve("call Bob, I mean call Sue, I mean call Ann"),
                       "call Ann")
    }
}
