import XCTest
@testable import PUSHCore

final class WhisperModelTests: XCTestCase {

    /// The raw value is a UserDefaults persistence key. Changing it silently
    /// resets every existing user's engine choice.
    func testRawValueIsStableForPersistence() {
        XCTAssertEqual(WhisperModel.nemotronMultilingual.rawValue, "nemotron-multilingual")
    }

    /// Only the multilingual engines take a language; the English ones must not
    /// grow a picker.
    func testOnlyMultilingualEnginesAcceptALanguage() {
        XCTAssertTrue(WhisperModel.nemotronMultilingual.supportsLanguageSelection)
        XCTAssertFalse(WhisperModel.parakeetUnified.supportsLanguageSelection)
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
