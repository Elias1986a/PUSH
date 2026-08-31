import XCTest
import Foundation
@testable import PUSHCore

final class DictationLanguageTests: XCTestCase {

    /// The display name comes from the OS, not a table we maintain — a
    /// hardcoded list is the thing this type exists to avoid.
    func testDisplayNameIsLocalizedFromCode() {
        let pt = DictationLanguage(code: "pt-BR")
        XCTAssertTrue(pt.displayName.contains("Portuguese"), "got \(pt.displayName)")
    }

    /// Sorting is by display name so the picker reads alphabetically to a human,
    /// not by raw code.
    func testSortsByDisplayName() {
        let sorted = [DictationLanguage(code: "fr-FR"),
                      DictationLanguage(code: "de-DE"),
                      DictationLanguage(code: "es-ES")].sorted()
        let expected = ["fr-FR", "de-DE", "es-ES"].sorted {
            (Locale.current.localizedString(forIdentifier: $0) ?? $0) <
            (Locale.current.localizedString(forIdentifier: $1) ?? $1)
        }
        XCTAssertEqual(sorted.map(\.code), expected)
    }

    /// English is special-cased downstream (post-processing is English-only),
    /// so the test pins the predicate rather than leaving it implicit.
    func testIsEnglishRecognisesRegionalVariants() {
        XCTAssertTrue(DictationLanguage(code: "en-US").isEnglish)
        XCTAssertTrue(DictationLanguage(code: "en").isEnglish)
        XCTAssertFalse(DictationLanguage(code: "es-ES").isEnglish)
    }
}
