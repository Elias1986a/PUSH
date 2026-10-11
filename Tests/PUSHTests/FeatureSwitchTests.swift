import XCTest
@testable import PUSH

/// Suites, never `.standard`: that is the running app's config.
@MainActor
final class FeatureSwitchTests: XCTestCase {
    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "FeatureSwitchTests.\(name)")!
        d.removePersistentDomain(forName: "FeatureSwitchTests.\(name)")
        return d
    }

    func testDictationDefaultsOnWhenKeyAbsent() {
        XCTAssertTrue(FeatureSwitches.dictationEnabled(in: freshDefaults()))
    }

    func testTypeDefaultsOff() {
        XCTAssertFalse(FeatureSwitches.typeEnabled(in: freshDefaults()))
    }

    func testStoredValuesWin() {
        let d = freshDefaults()
        d.set(false, forKey: FeatureSwitches.dictationKey)
        d.set(true, forKey: FeatureSwitches.typeKey)
        XCTAssertFalse(FeatureSwitches.dictationEnabled(in: d))
        XCTAssertTrue(FeatureSwitches.typeEnabled(in: d))
    }

    func testNeitherSwitchIsSynced() {
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(FeatureSwitches.dictationKey))
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(FeatureSwitches.typeKey))
    }
}
