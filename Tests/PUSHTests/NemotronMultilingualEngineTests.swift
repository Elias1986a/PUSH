import XCTest
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

    /// "auto" must never reach the engine — this app always picks a language.
    /// If it somehow does, fall back to English rather than enabling detection.
    func testAutoIsRejectedInFavourOfExplicitEnglish() {
        XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: "auto"), "latin")
    }

    /// The language list must come from the loaded model, never a constant.
    func testSupportedLanguagesIsEmptyUntilTheModelIsLoaded() async {
        let languages = await NemotronMultilingualEngine.shared.supportedLanguages()
        if !NemotronMultilingualEngine.isModelDownloaded() {
            XCTAssertTrue(languages.isEmpty,
                          "no model on disk means no list — never a hardcoded fallback")
        }
    }
}
