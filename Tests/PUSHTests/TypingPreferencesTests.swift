import XCTest
@testable import PUSH
import PUSHCore

/// Suites, never `.standard`: that is the running app's config.
final class TypingPreferencesTests: XCTestCase {
    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "TypingPreferencesTests.\(name)")!
        d.removePersistentDomain(forName: "TypingPreferencesTests.\(name)")
        return d
    }

    func testDefaults() {
        let d = freshDefaults()
        XCTAssertEqual(TypingPreferences.model(in: d), .recommended)
        XCTAssertEqual(TypingPreferences.length(in: d), .short)
    }

    func testStoredValuesWinAndUnknownOnesFallBack() {
        let d = freshDefaults()
        d.set("gemma4-e2b-base", forKey: TypingPreferences.modelKey)
        d.set("long", forKey: TypingPreferences.lengthKey)
        XCTAssertEqual(TypingPreferences.model(in: d), .best)
        XCTAssertEqual(TypingPreferences.length(in: d), .long)
        d.set("some-removed-model", forKey: TypingPreferences.modelKey)
        XCTAssertEqual(TypingPreferences.model(in: d), .recommended)
    }

    func testStoredLengthIsClampedToTheModel() {
        let d = freshDefaults()
        d.set("qwen3.5-0.8b-base", forKey: TypingPreferences.modelKey)
        d.set("long", forKey: TypingPreferences.lengthKey)
        XCTAssertEqual(TypingPreferences.length(in: d), .short)
    }

    @MainActor
    func testNeitherIsSynced() {
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(TypingPreferences.modelKey))
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(TypingPreferences.lengthKey))
    }

    func testModelsLiveUnderApplicationSupport() {
        let dir = TypingModelStore.directory.path
        XCTAssertTrue(dir.hasSuffix("Application Support/PUSH/TypingModels"), dir)
    }
}
