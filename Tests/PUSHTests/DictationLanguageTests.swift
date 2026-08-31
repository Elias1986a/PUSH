import XCTest
import Foundation
@testable import PUSHCore

final class DictationLanguageTests: XCTestCase {

    /// Naming is pinned to a fixed locale rather than `.current` so the
    /// expectations don't depend on how the machine running the suite is set up.
    private let en = Locale(identifier: "en_US")

    // MARK: - Display name

    /// The display name comes from the OS, not a table we maintain — a
    /// hardcoded list is the thing this type exists to avoid.
    func testDisplayNameIsLocalizedFromCode() {
        XCTAssertEqual(DictationLanguage(code: "pt-BR").displayName(in: en), "Portuguese (Brazil)")
        XCTAssertEqual(DictationLanguage(code: "de-DE").displayName(in: en), "German (Germany)")
    }

    /// The regression that motivated the subtag fallback: taking the first two
    /// characters of the code named a *different* language. Each of these was
    /// verified wrong under `String(code.prefix(2))` — "fil" read as Finnish,
    /// "haw" as Hausa, "ceb" as Chechen, "tlh" as Tagalog.
    func testDisplayNameFallsBackToParsedSubtagNotFirstTwoCharacters() {
        XCTAssertEqual(DictationLanguage(code: "fil-XX").displayName(in: en), "Filipino")
        XCTAssertEqual(DictationLanguage(code: "haw-XX").displayName(in: en), "Hawaiian")
        XCTAssertEqual(DictationLanguage(code: "ceb-XX").displayName(in: en), "Cebuano")
        XCTAssertEqual(DictationLanguage(code: "tlh-XX").displayName(in: en), "Klingon")
    }

    /// Last resort: a code the OS cannot name at all shows as itself. Telling
    /// the truth beats inventing a language.
    func testDisplayNameFallsBackToRawCodeWhenOSCannotNameIt() {
        XCTAssertEqual(DictationLanguage(code: "xx").displayName(in: en), "xx")
        XCTAssertEqual(DictationLanguage(code: "zzzz").displayName(in: en), "zzzz")
    }

    /// An empty code is a real outcome (a malformed metadata entry), so pin it:
    /// canonicalization turns it into the "undetermined" subtag, which the OS
    /// does name. The picker row reads "Unknown language" rather than blank.
    func testEmptyCodeBecomesUndeterminedRatherThanBlank() {
        let empty = DictationLanguage(code: "")
        XCTAssertEqual(empty.code, "und")
        XCTAssertEqual(empty.displayName(in: en), "Unknown language")
        XCTAssertFalse(empty.isEnglish)
    }

    // MARK: - Canonicalization

    /// The collision this type has to absorb: Apple Speech reports "en_US",
    /// Nemotron reports "en-US", and both lists reach the same picker.
    func testUnderscoreAndHyphenFormsCollapseToOneValue() {
        let apple = DictationLanguage(code: "en_US")
        let nemotron = DictationLanguage(code: "en-US")
        XCTAssertEqual(apple, nemotron)
        XCTAssertEqual(apple.code, "en-US")
        XCTAssertEqual(apple.hashValue, nemotron.hashValue)
        XCTAssertEqual(Set([apple, nemotron]).count, 1)
    }

    /// Canonicalization must not mangle codes the engines actually emit.
    func testCanonicalizationPreservesRealisticCodes() {
        XCTAssertEqual(DictationLanguage(code: "pt-BR").code, "pt-BR")
        XCTAssertEqual(DictationLanguage(code: "zh-Hant").code, "zh-Hant")
        XCTAssertEqual(DictationLanguage(code: "es-419").code, "es-419")
        XCTAssertEqual(DictationLanguage(code: "sr-Latn-RS").code, "sr-Latn-RS")
        XCTAssertEqual(DictationLanguage(code: "xx").code, "xx")
        // Case folding and ISO 639-2/3 -> 639-1 come free with the same pass.
        XCTAssertEqual(DictationLanguage(code: "EN").code, "en")
        XCTAssertEqual(DictationLanguage(code: "eng").code, "en")
    }

    // MARK: - isEnglish

    /// English is special-cased downstream (post-processing is English-only),
    /// so the test pins the predicate rather than leaving it implicit.
    func testIsEnglishRecognisesRegionalVariants() {
        for code in ["en", "en-US", "EN", "eng", "en_US", "en-GB"] {
            XCTAssertTrue(DictationLanguage(code: code).isEnglish, "expected \(code) to be English")
        }
    }

    /// The over-match that motivated parsing the subtag: these all begin "en"
    /// but none of them is English, and treating them as English would run the
    /// English-only rewrites over their transcripts.
    func testIsEnglishRejectsOtherLanguagesBeginningWithEN() {
        for code in ["enq", "enb", "enm", "ang", "es-ES", ""] {
            XCTAssertFalse(DictationLanguage(code: code).isEnglish, "expected \(code) not to be English")
        }
    }

    // MARK: - Identity and ordering

    /// The Picker tag and the UserDefaults round-trip both key off the code, so
    /// equality has to be the code and nothing else — not the display name,
    /// which varies with the reader's locale.
    func testEqualityAndHashAreCodeBased() {
        XCTAssertEqual(DictationLanguage(code: "es-ES"), DictationLanguage(code: "es-ES"))
        XCTAssertNotEqual(DictationLanguage(code: "es-ES"), DictationLanguage(code: "es-MX"))
        // Same display name, different code: still two distinct languages.
        XCTAssertNotEqual(DictationLanguage(code: "fil-XX"), DictationLanguage(code: "fil-YY"))
    }

    /// Sorting is by display name so the picker reads alphabetically to a human,
    /// not by raw code. Skipped off an English OS locale rather than left to
    /// fail there, since the expected order is written out in English.
    func testSortsByDisplayName() throws {
        try XCTSkipUnless(Locale.current.language.languageCode?.identifier == "en",
                          "expected order is written in English")
        let sorted = [DictationLanguage(code: "fr-FR"),
                      DictationLanguage(code: "de-DE"),
                      DictationLanguage(code: "es-ES")].sorted()
        // French (France) < German (Germany) < Spanish (Spain) — which is not
        // the order the raw codes would give.
        XCTAssertEqual(sorted.map(\.code), ["fr-FR", "de-DE", "es-ES"])
    }

    /// `==` is code-based while `<` is name-based, so ordering needs a tie-break
    /// to stay trichotomous. "fil-XX" and "fil-YY" are both "Filipino": exactly
    /// one of `a < b`, `a == b`, `b < a` must hold.
    func testOrderingIsTrichotomousWhenDisplayNamesMatch() {
        let a = DictationLanguage(code: "fil-XX")
        let b = DictationLanguage(code: "fil-YY")
        XCTAssertEqual(a.displayName(in: en), b.displayName(in: en))
        XCTAssertEqual([a < b, a == b, b < a].filter { $0 }.count, 1)
        XCTAssertTrue(a < b, "tie should break on the code")
    }

    /// The canonicalized pair is genuinely equal, so neither orders before the
    /// other — the case the tie-break exists to keep consistent.
    func testOrderingIsTrichotomousForCanonicalizedPair() {
        let a = DictationLanguage(code: "en_US")
        let b = DictationLanguage(code: "en-US")
        XCTAssertEqual([a < b, a == b, b < a].filter { $0 }.count, 1)
        XCTAssertTrue(a == b)
    }
}
