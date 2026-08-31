import XCTest
@testable import PUSH
@testable import PUSHCore

@MainActor
final class LanguagePreferenceTests: XCTestCase {

    /// A throwaway defaults suite, never `UserDefaults.standard`.
    ///
    /// `AppState.shared` is a singleton wired to the *user's live app
    /// configuration*. A test that wrote a language through it would leave the
    /// real PUSH dictating in whatever language this file happened to pick,
    /// with nothing on screen connecting the two — a bug the user could only
    /// find by dictating into it. So the store is injected instead, and the
    /// whole suite is deleted afterwards.
    private static let suiteName = "PUSHTests.LanguagePreference"

    /// Points `AppState`'s language storage at a scratch suite for the length
    /// of one test, and guarantees the suite is gone again afterwards.
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

    /// Independent keys: choosing Portuguese on Nemotron must not change what
    /// Apple Speech uses, since the two engines support different sets.
    func testEachEngineStoresItsOwnLanguage() {
        useIsolatedStore()
        let state = AppState.shared
        state.setLanguage(DictationLanguage(code: "pt-BR"), for: .nemotronMultilingual)
        state.setLanguage(DictationLanguage(code: "fr-FR"), for: .appleSpeech)
        XCTAssertEqual(state.language(for: .nemotronMultilingual).code, "pt-BR")
        XCTAssertEqual(state.language(for: .appleSpeech).code, "fr-FR")
    }

    /// A fresh install must behave exactly as it does today: English.
    func testDefaultsToEnglish() {
        useIsolatedStore()
        XCTAssertTrue(AppState.shared.language(for: .nemotronMultilingual).isEnglish)
    }

    /// A preference persisted in Apple's underscore form must still match an
    /// offered hyphenated code — this is why DictationLanguage canonicalizes,
    /// and why `language(for:)` constructs one instead of comparing the stored
    /// string directly.
    func testLegacyUnderscoreCodeStillMatches() {
        let store = useIsolatedStore()
        store.set("en_US", forKey: WhisperModel.appleSpeech.languageDefaultsKey)
        XCTAssertEqual(AppState.shared.language(for: .appleSpeech),
                       DictationLanguage(code: "en-US"))
    }

    /// The real defaults domain must come out of a test run byte-identical.
    /// Belt and braces on top of the injected store: if someone later reaches
    /// for `UserDefaults.standard` in this file, this fails.
    func testTheRealDefaultsDomainIsNeverWritten() {
        let keys = WhisperModel.allCases.map(\.languageDefaultsKey)
        let before = keys.map { UserDefaults.standard.string(forKey: $0) }

        useIsolatedStore()
        AppState.shared.setLanguage(DictationLanguage(code: "ja-JP"), for: .nemotronMultilingual)

        let after = keys.map { UserDefaults.standard.string(forKey: $0) }
        XCTAssertEqual(before, after)
    }
}
