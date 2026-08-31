import XCTest
@testable import PUSH
@testable import PUSHCore

/// The post-processing chain is English — English number grammar, English
/// orthography, an English filler-word list. These tests pin the gate that
/// keeps it off every other language.
///
/// Each non-English case below is a corruption measured against the real chain,
/// not a hypothetical: the English path turns Spanish "ten cuidado" into
/// "10 cuidado", eats the German preposition "um" as a filler, and capitalises
/// the Italian article "i". A correct transcript came in and a wrong one came
/// out, which is the worst thing this app can do.
@MainActor
final class LanguageGateTests: XCTestCase {

    private let english = DictationLanguage(code: "en-US")
    private let spanish = DictationLanguage(code: "es-ES")
    private let portuguese = DictationLanguage(code: "pt-BR")
    private let italian = DictationLanguage(code: "it-IT")
    private let german = DictationLanguage(code: "de-DE")

    // MARK: - The English-only passes

    /// Spoken-number conversion is English arithmetic. "vinte e cinco" is not
    /// "twenty five", and running the English path over Portuguese can only
    /// damage a correct transcript.
    func testNumberConversionIsSkippedForNonEnglish() {
        // Spanish "ten cuidado" ("be careful") is not the number ten.
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("ten cuidado con el perro",
                                              hasNativePunctuation: true,
                                              language: spanish),
            "ten cuidado con el perro")
        // The corruption this prevents, stated outright.
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("ten cuidado con el perro",
                                              hasNativePunctuation: true),
            "10 cuidado con el perro")

        // Portuguese numbers are left as words rather than half-translated.
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("vinte e cinco anos",
                                              hasNativePunctuation: true,
                                              language: portuguese),
            "vinte e cinco anos")

        // English number words *inside* a non-English transcript stay put too:
        // the gate is on the chosen language, not on what the words look like.
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("twenty five",
                                              hasNativePunctuation: true,
                                              language: portuguese),
            "twenty five")
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("twenty five", hasNativePunctuation: true),
            "25")
    }

    /// The filler list is an English word list. German "um" is a preposition
    /// ("um die zwanzig" — around twenty); stripping it deletes a real word.
    func testFillerRemovalIsSkippedForNonEnglish() {
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("das ist so um die zwanzig",
                                              hasNativePunctuation: true,
                                              language: german),
            "das ist so um die zwanzig")
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("das ist so um die zwanzig",
                                              hasNativePunctuation: true),
            "das ist so die zwanzig")
    }

    /// The standalone "i" → "I" rule is English orthography. In Italian "i" is a
    /// definite article and capitalising it is a straightforward corruption.
    ///
    /// Driven with `hasNativePunctuation: false` because every engine PUSH ships
    /// today punctuates natively, which already skips this pass. The gate still
    /// belongs at the chain level: `hasNativePunctuation` is a property of the
    /// engine and the language is a property of the user's choice, and neither
    /// should depend on the other holding.
    func testCapitalizeIIsSkippedForNonEnglish() {
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("Ho visto i gatti",
                                              hasNativePunctuation: false,
                                              language: italian),
            "Ho visto i gatti")
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("Ho visto i gatti", hasNativePunctuation: false),
            "Ho visto I gatti.")
    }

    // MARK: - The 99% case

    /// English behaviour must be bit-identical to before this change. The
    /// regression guard proper is the 46 untouched tests in
    /// `TextProcessingTests`; this pins the two things those cannot see — that
    /// the new parameter *defaults* to English, and that every spelling of
    /// English reaches the same path `DictationLanguage.isEnglish` promises.
    func testEnglishPathIsUnchanged() {
        let corpus = [
            "four point eight million",
            "twelve thousand dollars",
            "three point one four",
            "one thousand people",
            "two thousand twenty four",
            "twenty-five years",
            "i was, like, going to the thirty first",
            "'cause i said so",
            "50 percent off",
            "um so i think it's fine",
            // A non-English string still runs the English chain when English is
            // what the user chose — the gate reads the preference, not the text.
            "ten cuidado con el perro"
        ]
        for text in corpus {
            for native in [true, false] {
                let baseline = TranscriptionPipeline.postProcess(text, hasNativePunctuation: native)
                for spelling in ["en-US", "en-GB", "en_US", "EN", "eng", "en"] {
                    XCTAssertEqual(
                        TranscriptionPipeline.postProcess(text,
                                                          hasNativePunctuation: native,
                                                          language: DictationLanguage(code: spelling)),
                        baseline,
                        "\(spelling) diverged from the default English path on \"\(text)\"")
                }
            }
        }

        // Spot values, so "unchanged" cannot quietly mean "uniformly broken".
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("twelve thousand dollars",
                                              hasNativePunctuation: true,
                                              language: english),
            "$12,000")
        XCTAssertEqual(
            TranscriptionPipeline.postProcess("four point eight million",
                                              hasNativePunctuation: true,
                                              language: english),
            "4.8 million")
    }

    // MARK: - Resolving the active language

    /// A throwaway defaults suite, never `UserDefaults.standard` — `AppState
    /// .shared` is wired to the user's live configuration, and a test that wrote
    /// a language through it would leave the real PUSH dictating in whatever
    /// language this file happened to pick.
    private static let suiteName = "PUSHTests.LanguageGate"

    @discardableResult
    private func useIsolatedStore() -> UserDefaults {
        let suite = UserDefaults(suiteName: Self.suiteName)!
        suite.removePersistentDomain(forName: Self.suiteName)
        AppState.shared.languageDefaults = suite
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: Self.suiteName)
            MainActor.assumeIsolated { AppState.shared.languageDefaults = .standard }
        }
        return suite
    }

    /// An English-only engine must get English post-processing even if a stale
    /// language key exists for it in defaults.
    ///
    /// The Parakeet engines are English by construction and have no picker, so
    /// nothing in the UI can write these keys — but a key left behind by an
    /// earlier build, a hand-edited plist or a synced defaults domain would
    /// otherwise silently disable English post-processing for the default
    /// engine, and the user would have no setting to point at.
    func testEnglishOnlyEnginesAlwaysGetEnglishProcessing() {
        let store = useIsolatedStore()
        for model in [WhisperModel.parakeetUnified, .parakeetStreaming, .parakeetV2] {
            store.set("pt-BR", forKey: model.languageDefaultsKey)
            XCTAssertTrue(TranscriptionPipeline.activeLanguage(for: model).isEnglish,
                          "\(model.rawValue) honoured a language key it has no picker for")
        }

        // The engines that *do* have a picker still honour it.
        store.set("pt-BR", forKey: WhisperModel.nemotronMultilingual.languageDefaultsKey)
        XCTAssertEqual(TranscriptionPipeline.activeLanguage(for: .nemotronMultilingual).code, "pt-BR")
    }

    /// With nothing stored, every engine is English — a fresh install must
    /// behave exactly as it does today.
    func testActiveLanguageDefaultsToEnglish() {
        useIsolatedStore()
        for model in WhisperModel.allCases {
            XCTAssertTrue(TranscriptionPipeline.activeLanguage(for: model).isEnglish)
        }
    }
}
