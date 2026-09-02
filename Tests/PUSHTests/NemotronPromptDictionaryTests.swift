import XCTest
@testable import PUSHCore

/// What the dictation language picker offers, and why it is not simply the
/// model's `prompt_dictionary` keys.
///
/// The dictionary is a forgiving lookup table: the `latin` build spells 84
/// prompts with 121 keys. Offered raw it produced a picker with "English" and
/// "English (United States)" as separate rows for the same prompt, plus `enGB`
/// and `esES` shown as themselves because macOS has no name for them.
///
/// Everything here runs against `realPromptDictionary` — a verbatim copy of the
/// shipped `metadata.json`, so the suite needs no 600 MB download — and
/// `testFixtureStillMatchesTheModelOnDisk` fails the day the copy goes stale.
final class NemotronPromptDictionaryTests: XCTestCase {

    /// `nemotron-multilingual/latin/2240ms/metadata.json`, `prompt_dictionary`,
    /// verbatim. 121 keys, 84 distinct prompt ids.
    static let realPromptDictionary: [String: Int] = [
        "en": 0, "en-US": 0, "en-GB": 1, "enGB": 1,
        "es-ES": 2, "esES": 2, "es": 3, "es-US": 3,
        "zh-CN": 4, "zh-ZH": 4, "zh-TW": 5, "hi": 6,
        "hi-HI": 6, "hi-IN": 6, "ar": 7, "ar-AR": 7,
        "fr": 8, "fr-FR": 8, "de": 9, "de-DE": 9,
        "ja-JA": 10, "ja-JP": 10, "ru": 11, "ru-RU": 11,
        "pt-BR": 12, "pt": 13, "pt-PT": 13, "ko": 14,
        "ko-KO": 14, "ko-KR": 14, "it": 15, "it-IT": 15,
        "nl": 16, "nl-NL": 16, "pl": 17, "pl-PL": 17,
        "tr": 18, "tr-TR": 18, "uk": 19, "uk-UA": 19,
        "ro": 20, "ro-RO": 20, "el": 21, "el-GR": 21,
        "cs": 22, "cs-CZ": 22, "hu": 23, "hu-HU": 23,
        "sv": 24, "sv-SE": 24, "da": 25, "da-DK": 25,
        "fi": 26, "fi-FI": 26, "no": 27, "no-NO": 27,
        "sk": 28, "sk-SK": 28, "hr": 29, "hr-HR": 29,
        "bg": 30, "bg-BG": 30, "lt": 31, "lt-LT": 31,
        "th-TH": 32, "vi-VN": 33, "id-ID": 34, "ms-MY": 35,
        "bn-IN": 36, "ur-PK": 37, "fa-IR": 38, "ta-IN": 39,
        "te-IN": 40, "mr-IN": 41, "gu-IN": 42, "kn-IN": 43,
        "ml-IN": 44, "si-LK": 45, "ne-NP": 46, "km-KH": 47,
        "sw-KE": 48, "am-ET": 49, "ha-NG": 50, "zu-ZA": 51,
        "yo-NG": 52, "ig-NG": 53, "af-ZA": 54, "rw-RW": 55,
        "so-SO": 56, "ny-MW": 57, "ln-CD": 58, "or-KE": 59,
        "et": 60, "et-EE": 60, "lv": 61, "lv-LV": 61,
        "sl": 62, "sl-SI": 62, "he-IL": 64, "ku-TR": 65,
        "az-AZ": 66, "ka-GE": 67, "hy-AM": 68, "uz-UZ": 69,
        "tg-TJ": 70, "ky-KG": 71, "qu-PE": 80, "ay-BO": 81,
        "gn-PY": 82, "nah-MX": 83, "mi-NZ": 96, "haw-US": 97,
        "sm-WS": 98, "to-TO": 99, "fr-CA": 100, "auto": 101,
        "mt-MT": 102, "nb": 103, "nb-NO": 103, "nn": 104,
        "nn-NO": 104
    ]

    private lazy var offered = NemotronPromptDictionary.offeredLanguages(
        in: Self.realPromptDictionary)
    private lazy var codes = Set(offered.map(\.code))

    // MARK: - The shape of the result

    /// The headline: 121 keys in, one row per usable prompt out.
    ///
    /// `auto` (101) is deliberately not a language, and 27 is Norwegian Bokmål
    /// a second time — see `testNorwegianIsOfferedOnceDespiteTwoPrompts`. Every
    /// other prompt id keeps exactly one row.
    func testOneRowPerUsablePromptId() {
        let ids = Set(Self.realPromptDictionary.values)
        XCTAssertEqual(Self.realPromptDictionary.count, 121, "fixture changed")
        XCTAssertEqual(ids.count, 84, "fixture changed")
        XCTAssertEqual(offered.count, ids.count - 2,
                       "expected one row per prompt id, less `auto` and the duplicate Bokmål")
        XCTAssertEqual(offered.count, Set(offered).count, "rows must be distinct")
    }

    /// The point of the exercise: no row the user cannot make sense of. A code
    /// macOS cannot name reaches the picker as the raw string.
    ///
    /// `nah-MX` is the single exception and stays in the list. macOS has no
    /// name for Nahuatl at all — not for the region pair, not for `nah` alone
    /// — so its row does read "nah-MX". It is also the only key for prompt 83,
    /// and hiding a language the model can transcribe is the worse bug of the
    /// two. Pinned so it stays *one* row, not a class of them.
    func testEveryOfferedCodeHasANameExceptNahuatl() {
        let en = Locale(identifier: "en_US")
        let unnameable = offered.filter { en.localizedString(forIdentifier: $0.code) == nil }
        XCTAssertEqual(unnameable.map(\.code), ["nah-MX"],
                       "a row macOS cannot name would be shown as its raw code")
    }

    /// Two rows reading "Norwegian Bokmål (Norway)" is not merely untidy: the
    /// Picker tags rows by identity and the two would be `==`.
    func testNoTwoRowsShareAName() {
        let en = Locale(identifier: "en_US")
        let names = offered.map { $0.displayName(in: en) }
        XCTAssertEqual(names.count, Set(names).count,
                       "duplicate names: \(names.filter { n in names.filter { $0 == n }.count > 1 })")
    }

    /// Whatever we offer goes straight back through FluidAudio's lookup, which
    /// checks the dictionary first. A code that is not a key of it resolves by
    /// fallback — to a different prompt than the one it was chosen to name.
    func testEveryOfferedCodeIsAVerbatimKey() {
        for language in offered {
            XCTAssertNotNil(Self.realPromptDictionary[language.code],
                            "\(language.code) is not a key and would resolve by fallback")
        }
    }

    /// Rule 4 of the exercise, and the one that constrains everything else:
    /// de-duplicating must not cost the user a language.
    func testEveryPromptIdIsStillReachable() {
        let reachable = Set(offered.compactMap { Self.realPromptDictionary[$0.code] })
        let expected = Set(Self.realPromptDictionary.values).subtracting([101, 27])
        XCTAssertEqual(reachable, expected,
                       "unreachable prompts: \(expected.subtracting(reachable).sorted())")
    }

    // MARK: - What gets dropped

    /// `auto` is a real key (101) and the one option this app never offers.
    func testAutoIsNeverOffered() {
        XCTAssertFalse(codes.contains { $0.lowercased().hasPrefix("auto") })
    }

    /// The two keys that are not BCP-47 at all. Canonicalization does not
    /// repair them — they come out `engb` and `eses` — and both share a prompt
    /// with a well-formed sibling, so dropping them costs nothing.
    func testMalformedKeysAreDropped() {
        for bad in ["enGB", "esES", "engb", "eses"] {
            XCTAssertFalse(codes.contains(bad), "\(bad) reached the picker")
        }
        XCTAssertTrue(codes.contains("en-GB"))
        XCTAssertTrue(codes.contains("es-ES"))
    }

    /// The invented regionals: the "region" is the language code shouted, and
    /// none of ZH, JA, KO, HI is an ISO 3166 country.
    func testInventedRegionalsAreDropped() {
        for bad in ["zh-ZH", "ja-JA", "ko-KO", "hi-HI"] {
            XCTAssertFalse(codes.contains(bad), "\(bad) reached the picker")
        }
        for good in ["zh-CN", "ja-JP", "ko-KR", "hi-IN"] {
            XCTAssertTrue(codes.contains(good), "\(good) went missing with its bad sibling")
        }
    }

    /// The trap in the rule above, and the reason it tests the region rather
    /// than the repeated letters. These eight look exactly like `zh-ZH` and are
    /// nothing like it: the regions are real, and each is the *only* key for
    /// its prompt. A pattern match would have deleted eight languages.
    func testRealRegionsThatHappenToEchoTheirLanguageSurvive() {
        for code in ["so-SO", "th-TH", "az-AZ", "uz-UZ", "id-ID", "mt-MT", "to-TO", "rw-RW"] {
            XCTAssertTrue(codes.contains(code), "\(code) was mistaken for an invented regional")
        }
    }

    // MARK: - Which spelling wins

    /// A region that says something about the language beats no region.
    func testRegionalSpellingBeatsBareLanguage() {
        XCTAssertTrue(codes.contains("en-US")); XCTAssertFalse(codes.contains("en"))
        XCTAssertTrue(codes.contains("pt-PT")); XCTAssertFalse(codes.contains("pt"))
        XCTAssertTrue(codes.contains("de-DE")); XCTAssertFalse(codes.contains("de"))
        XCTAssertTrue(codes.contains("hi-IN")); XCTAssertFalse(codes.contains("hi"))
    }

    /// Unless the pair names no locale that exists. `AR` is Argentina, so
    /// `ar-AR` clears every structural check, and macOS names that prompt
    /// "Arabic (Argentina)". The bare `ar` shares the prompt, so it wins.
    func testBareLanguageBeatsARegionThatNamesNoRealLocale() {
        XCTAssertTrue(codes.contains("ar"), "expected plain Arabic")
        XCTAssertFalse(codes.contains("ar-AR"), "\"Arabic (Argentina)\" reached the picker")
    }

    /// The regression that rule cost on the first attempt. Sixteen languages
    /// spell themselves `xx-XX` legitimately, and demoting them on the
    /// repeated letters left "Portuguese" beside "Portuguese (Brazil)" with
    /// nothing to say the first one was European.
    func testLanguagesWhoseRegionRepeatsTheirCodeKeepIt() {
        for code in ["fr-FR", "pt-PT", "de-DE", "it-IT", "nl-NL", "pl-PL", "tr-TR", "ru-RU",
                     "ro-RO", "hu-HU", "sk-SK", "hr-HR", "bg-BG", "lt-LT", "lv-LV", "fi-FI"] {
            XCTAssertTrue(codes.contains(code), "\(code) lost its region")
        }
    }

    /// The three the locale check also fires on, where the model is right and
    /// macOS simply ships no such locale. Each is the only key for its prompt,
    /// so a rejection here would have deleted three languages.
    func testUnknownLocalesWithNoRivalSpellingSurvive() {
        for code in ["ay-BO", "nah-MX", "or-KE"] {
            XCTAssertTrue(codes.contains(code), "\(code) was dropped and orphaned its prompt")
        }
    }

    /// Brazilian and European Portuguese are different prompts (12 and 13) and
    /// audibly different models of the language. Collapsing them would look
    /// like tidying and would cost a user their variety.
    func testBothPortugueseVariantsSurvive() {
        XCTAssertTrue(codes.contains("pt-BR"))
        XCTAssertTrue(codes.contains("pt-PT"))
        XCTAssertEqual(Self.realPromptDictionary["pt-BR"], 12)
        XCTAssertEqual(Self.realPromptDictionary["pt-PT"], 13)
    }

    /// Likewise the four other genuine region pairs.
    func testGenuineRegionPairsBothSurvive() {
        for (a, b) in [("en-US", "en-GB"), ("es-ES", "es-US"),
                       ("zh-CN", "zh-TW"), ("fr-FR", "fr-CA")] {
            XCTAssertTrue(codes.contains(a), "\(a) went missing")
            XCTAssertTrue(codes.contains(b), "\(b) went missing")
            XCTAssertNotEqual(Self.realPromptDictionary[a], Self.realPromptDictionary[b])
        }
    }

    /// The collision the canonicalization creates rather than removes: the
    /// model carries Bokmål twice, as `no`/`no-NO` (27) and `nb`/`nb-NO` (103),
    /// and ICU folds the deprecated `no` onto `nb`. Only one row can exist, and
    /// it has to be the one FluidAudio's lookup answers — `nb-NO` is a literal
    /// key of 103, `no-NO` canonicalizes away from its own id.
    ///
    /// Nynorsk (104) is a separate language and keeps its own row.
    func testNorwegianIsOfferedOnceDespiteTwoPrompts() {
        XCTAssertEqual(codes.intersection(["nb", "nb-NO", "no", "no-NO"]), ["nb-NO"])
        XCTAssertEqual(Self.realPromptDictionary["nb-NO"], 103)
        XCTAssertTrue(codes.contains("nn-NO"), "Nynorsk is not a duplicate of Bokmål")
    }

    // MARK: - Robustness

    /// A dictionary has no order. Ties broken by anything less than a total
    /// rule would let the offered list change between launches.
    func testTheResultIsDeterministic() {
        let first = NemotronPromptDictionary.offeredLanguages(in: Self.realPromptDictionary)
        for _ in 0..<25 {
            XCTAssertEqual(
                NemotronPromptDictionary.offeredLanguages(in: Self.realPromptDictionary), first)
        }
    }

    /// Nothing loaded means no list — never a hardcoded one. A picker that
    /// disagrees with the model offers a language the encoder cannot serve.
    func testAnEmptyDictionaryOffersNothing() {
        XCTAssertEqual(NemotronPromptDictionary.offeredLanguages(in: [:]), [])
        XCTAssertEqual(NemotronPromptDictionary.offeredLanguages(in: ["auto": 101]), [])
    }

    /// Sorted by name for a human, which `DictationLanguage` already promises;
    /// asserted here because the picker shows this array in order.
    func testTheListIsSortedForReading() {
        XCTAssertEqual(offered, offered.sorted())
    }

    /// The fixture above is a copy, and a copy can go stale — FluidAudio bumps
    /// the model, the dictionary grows a language, and every assertion here
    /// keeps passing against last year's list. Skips rather than fails when the
    /// build is not downloaded; nobody should need 600 MB to run the units.
    func testFixtureStillMatchesTheModelOnDisk() throws {
        let metadata = NemotronMultilingualEngine.modelDirectory(for: "es-ES")
            .appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadata) else {
            throw XCTSkip("Nemotron latin build not on disk — cannot check the fixture")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let onDisk = json?["prompt_dictionary"] as? [String: Int]
        XCTAssertEqual(onDisk, Self.realPromptDictionary,
                       "the shipped prompt dictionary has changed — update the fixture")
    }
}
