import XCTest
import FluidAudio
@testable import PUSHCore

final class NemotronMultilingualEngineTests: XCTestCase {

    /// The latin vocab is smaller and has a faster joint network. Routing must
    /// match FluidAudio's own mapping or we download the wrong 600 MB.
    func testLatinLanguagesRouteToTheLatinVocab() {
        for code in ["en-US", "es-ES", "fr-FR", "it-IT", "pt-BR", "de-DE"] {
            XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: code), "latin",
                           "\(code) should use the pruned latin vocab")
        }
    }

    func testNonLatinLanguagesRouteToTheFullVocab() {
        for code in ["zh-CN", "ja-JP", "ru-RU"] {
            XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: code), "multilingual")
        }
    }

    /// The drift guard the duplication exists to need. `vocabVariant(for:)`
    /// copies FluidAudio's split rather than calling it, so nothing but this
    /// test notices when a FluidAudio bump moves a language between the two
    /// builds — and the symptom of not noticing is a wrong 600 MB download.
    ///
    /// "auto" is excluded on purpose; it is the one deliberate divergence, and
    /// `testAutoNormalizesToACodeBothMappingsAgreeOn` covers it instead.
    func testVocabVariantMatchesFluidAudioExceptForAuto() {
        for code in ["en-US", "es-ES", "fr-FR", "it-IT", "pt-BR", "de-DE",
                     "zh-CN", "ja-JP", "ru-RU", "ko-KR", "ar-SA"] {
            XCTAssertEqual(
                NemotronMultilingualEngine.vocabVariant(for: code),
                StreamingNemotronMultilingualAsrManager.languageDirectory(for: code),
                "\(code) drifted from FluidAudio's mapping")
        }
    }

    /// "auto" must never reach the engine — this app always picks a language.
    /// If it somehow does, fall back to English rather than enabling detection.
    func testAutoIsRejectedInFavourOfExplicitEnglish() {
        XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: "auto"), "latin")
    }

    /// The bookkeeping-vs-download agreement, which is the whole reason `"auto"`
    /// is normalized before anything downstream sees it.
    ///
    /// Forwarding a raw `"auto"` to FluidAudio loads the `multilingual` build
    /// while we record `latin`; every later latin language then takes the
    /// cheap-switch path onto the wrong build, permanently. This asserts that
    /// what we forward is a code both mappings resolve the same way.
    func testAutoNormalizesToACodeBothMappingsAgreeOn() {
        let forwarded = NemotronMultilingualEngine.effectiveLanguageCode("auto")

        XCTAssertNotEqual(forwarded.lowercased(), "auto",
                          "a raw \"auto\" must never be forwarded to FluidAudio")
        XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: forwarded), "latin")
        XCTAssertEqual(
            StreamingNemotronMultilingualAsrManager.languageDirectory(for: forwarded), "latin",
            "our variant bookkeeping and FluidAudio's download path must name the same build")
    }

    /// Any code that isn't "auto" passes through untouched — normalization is
    /// one special case, not a rewrite of what the user picked.
    func testEffectiveLanguageCodeLeavesRealLanguagesAlone() {
        for code in ["en-US", "pt-BR", "ja-JP"] {
            XCTAssertEqual(NemotronMultilingualEngine.effectiveLanguageCode(code), code)
        }
    }

    /// The language list must come from the loaded model, never a constant.
    ///
    /// Uses a fresh instance rather than `shared` so this asserts on a developer
    /// machine that already has the model downloaded — guarding on
    /// `isModelDownloaded()` made it vacuously green exactly where a hardcoded
    /// fallback list would show up.
    func testSupportedLanguagesIsEmptyUntilTheModelIsLoaded() async {
        let engine = NemotronMultilingualEngine()
        let languages = await engine.supportedLanguages()
        XCTAssertTrue(languages.isEmpty,
                      "no model loaded means no list — never a hardcoded fallback")
    }

    /// A per-language answer is what warns before a surprise second download;
    /// it has to agree with the variant mapping it is built on.
    func testPerLanguageDownloadCheckFollowsTheVariantMapping() {
        let latinReady = NemotronMultilingualEngine.isModelDownloaded(for: "es-ES")
        XCTAssertEqual(latinReady, NemotronMultilingualEngine.isModelDownloaded(for: "de-DE"),
                       "languages sharing a build must share an answer")
        XCTAssertEqual(
            NemotronMultilingualEngine.isModelDownloaded(for: "ja-JP"),
            NemotronMultilingualEngine.isModelDownloaded(for: "ru-RU"),
            "languages sharing a build must share an answer")

        // The either-variant row can only ever be the more optimistic of the two.
        if latinReady {
            XCTAssertTrue(NemotronMultilingualEngine.isModelDownloaded())
        }
    }
}
