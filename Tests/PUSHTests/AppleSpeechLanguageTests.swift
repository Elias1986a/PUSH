import XCTest
@testable import PUSHCore

final class AppleSpeechLanguageTests: XCTestCase {

    /// The list must come from the OS, and must not be empty on a supported
    /// system — an empty list would silently present an empty picker.
    func testSupportedLanguagesComeFromTheSystem() async throws {
        guard #available(macOS 26, *), AppleSpeechEngine.isSupported else {
            throw XCTSkip("Apple Speech needs macOS 26")
        }
        let languages = await AppleSpeechEngine.supportedLanguages()
        XCTAssertFalse(languages.isEmpty)
        XCTAssertTrue(languages.contains { $0.isEnglish }, "en must always be offered")
    }

    /// Every offered language must actually resolve, or the picker can seat a
    /// choice that then fails to load.
    func testEveryOfferedLanguageResolves() async throws {
        guard #available(macOS 26, *), AppleSpeechEngine.isSupported else {
            throw XCTSkip("Apple Speech needs macOS 26")
        }
        for language in await AppleSpeechEngine.supportedLanguages().prefix(5) {
            let resolved = await AppleSpeechEngine.resolveLocale(preferred: language.code)
            XCTAssertNotNil(resolved, "\(language.code) was offered but does not resolve")
        }
    }

    /// The round-trip the picker performs must be lossless: a locale the system
    /// offers, turned into a DictationLanguage and back, must resolve to the
    /// same locale. This is where the underscore/hyphen split would bite.
    func testLanguageRoundTripsBackToTheSameLocale() async throws {
        guard #available(macOS 26, *), AppleSpeechEngine.isSupported else {
            throw XCTSkip("Apple Speech needs macOS 26")
        }
        for language in await AppleSpeechEngine.supportedLanguages().prefix(5) {
            let resolved = await AppleSpeechEngine.resolveLocale(preferred: language.code)
            XCTAssertEqual(DictationLanguage(code: resolved?.identifier ?? ""), language,
                           "\(language.code) did not round-trip")
        }
    }
}
