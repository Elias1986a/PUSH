import XCTest
@testable import PUSHCore

final class WhisperModelTests: XCTestCase {

    /// The raw value is a UserDefaults persistence key. Changing it silently
    /// resets every existing user's engine choice.
    func testRawValueIsStableForPersistence() {
        XCTAssertEqual(WhisperModel.nemotronMultilingual.rawValue, "nemotron-multilingual")
    }

    /// Streaming on an English Mac, for the words appearing as you speak;
    /// Ultra anywhere else, since Streaming is English only.
    func testTheDefaultFollowsTheMacsLanguage() {
        XCTAssertEqual(WhisperModel.defaultModel(for: ["en-US", "fr-FR"]), .parakeetStreaming)
        XCTAssertEqual(WhisperModel.defaultModel(for: ["en-GB"]), .parakeetStreaming)
        XCTAssertEqual(WhisperModel.defaultModel(for: ["de-DE", "en-US"]), .parakeetUltra)
        XCTAssertEqual(WhisperModel.defaultModel(for: ["ja-JP"]), .parakeetUltra)
        XCTAssertEqual(WhisperModel.defaultModel(for: []), .parakeetStreaming)
    }

    /// A saved choice of the retired Unified engine no longer decodes, so
    /// launch falls back to the default rather than to a model that is gone.
    func testTheRetiredUnifiedPreferenceNoLongerDecodes() {
        XCTAssertNil(WhisperModel(rawValue: "parakeet-unified"))
        XCTAssertEqual(WhisperModel.selectable.first, WhisperModel.defaultModel)
        XCTAssertEqual(Set(WhisperModel.selectable), Set(WhisperModel.allCases))
    }

    /// Only the multilingual engines take a language; the English ones must not
    /// grow a picker.
    func testOnlyMultilingualEnginesAcceptALanguage() {
        XCTAssertTrue(WhisperModel.nemotronMultilingual.supportsLanguageSelection)
        XCTAssertFalse(WhisperModel.parakeetStreaming.supportsLanguageSelection)
        XCTAssertFalse(WhisperModel.parakeetUltra.supportsLanguageSelection)
    }

    func testMultilingualEngineIsSelectable() {
        XCTAssertTrue(WhisperModel.selectable.contains(.nemotronMultilingual))
    }

    /// The key the app and the comparison tool both use to persist a language.
    /// It is derived from `rawValue` rather than written out twice precisely so
    /// the two packages cannot drift; pin the shape it derives.
    func testLanguageDefaultsKeyIsDerivedFromTheRawValue() {
        XCTAssertEqual(WhisperModel.nemotronMultilingual.languageDefaultsKey,
                       "language.nemotron-multilingual")
    }
}
