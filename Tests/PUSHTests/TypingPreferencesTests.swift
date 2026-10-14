import AppKit
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
        d.set("qwen3.5-2b-base", forKey: TypingPreferences.modelKey)
        d.set("long", forKey: TypingPreferences.lengthKey)
        XCTAssertEqual(TypingPreferences.length(in: d), .medium)
    }

    func testCodeEditorsAreOffByDefault() {
        let d = freshDefaults()
        XCTAssertFalse(TypingPreferences.codeEditors(in: d))
        d.set(true, forKey: TypingPreferences.codeEditorsKey)
        XCTAssertTrue(TypingPreferences.codeEditors(in: d))
    }

    @MainActor
    func testTheModelIsNeverSyncedAndTheRestOnlyCopiedOnRequest() {
        // A model is a download, so it never leaves the Mac.
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(TypingPreferences.modelKey))
        // Length and code editors are taste: copied once to a new Mac, never pushed onto an existing one.
        for key in [TypingPreferences.lengthKey, TypingPreferences.codeEditorsKey] {
            XCTAssertTrue(CloudSync.seededSettingKeys.contains(key))
            XCTAssertFalse(CloudSync.liveSettingKeys.contains(key))
        }
    }

    func testModelsLiveUnderApplicationSupport() {
        let dir = TypingModelStore.directory.path
        XCTAssertTrue(dir.hasSuffix("Application Support/PUSH/TypingModels"), dir)
    }

    func testNewSettingsDefaults() {
        let d = freshDefaults()
        XCTAssertEqual(TypingPreferences.color(in: d), .preset(.gray))
        XCTAssertTrue(TypingPreferences.spaceAfterLastWord(in: d))
        XCTAssertFalse(TypingPreferences.pauseOnBattery(in: d))
        XCTAssertEqual(TypingPreferences.excludedApps(in: d), [])
        XCTAssertNil(TypingPreferences.pausedUntil(in: d))
    }

    func testAPauseInThePastIsNoPause() {
        let d = freshDefaults()
        d.set(Date().addingTimeInterval(-60), forKey: TypingPreferences.pausedUntilKey)
        XCTAssertNil(TypingPreferences.pausedUntil(in: d))
        let later = Date().addingTimeInterval(3600)
        d.set(later, forKey: TypingPreferences.pausedUntilKey)
        XCTAssertEqual(TypingPreferences.pausedUntil(in: d), later)
    }

    func testSuggestionColorRoundTrips() {
        XCTAssertEqual(SuggestionColor(saved: "gray"), .preset(.gray))
        XCTAssertEqual(SuggestionColor(saved: "#ff8800"), .custom(hex: "#FF8800"))
        XCTAssertEqual(SuggestionColor(saved: "chartreuse"), .default)
        XCTAssertEqual(SuggestionColor(saved: "#12345"), .default)
        let custom = SuggestionColor(custom: NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
        XCTAssertEqual(custom, .custom(hex: "#FF8000"))
        XCTAssertEqual(SuggestionColor(saved: custom.saved), custom)
    }

    func testUserExcludedApps() {
        XCTAssertTrue(TypingExclusions.isExcluded(bundleID: "com.1password.1password"))
        XCTAssertFalse(TypingExclusions.isExcluded(bundleID: "com.apple.Notes"))
        XCTAssertTrue(TypingExclusions.isExcluded(bundleID: "com.apple.Notes", userExcluded: ["com.apple.notes"]))
    }

    func testSignOffNamePrefersTheUsersChoice() {
        XCTAssertEqual(TypingPreferences.signOffName(saved: "  Sam ", fullName: "Samuel Rivera"), "Sam")
        XCTAssertEqual(TypingPreferences.signOffName(saved: "", fullName: "Samuel Rivera"), "Samuel")
        XCTAssertNil(TypingPreferences.signOffName(saved: " ", fullName: ""))
    }
}
