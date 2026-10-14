import XCTest
@testable import PUSH

/// Which settings iCloud is allowed to carry between Macs.
///
/// The list is data, so nothing else pins it — and the one entry that had to
/// leave it is the one that cost a user a 600 MB download on a machine that had
/// never chosen the model, so it is worth a test that says why.
@MainActor
final class CloudSyncMirroredKeysTests: XCTestCase {

    /// A model is a download, not a preference. Syncing the choice makes one
    /// Mac's experiment another Mac's unattended 600 MB fetch at launch.
    func testTheModelChoiceIsNotMirrored() {
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains("selectedWhisperModel"))
    }

    /// Dropping it from the mirrored list only stops this Mac reading it; the
    /// value already in the store keeps arriving from Macs on older builds
    /// until someone removes it.
    func testTheModelChoiceIsRetiredFromTheStore() {
        XCTAssertTrue(CloudSync.retiredSettingKeys.contains("selectedWhisperModel"))
    }

    /// Nothing may be in both lists: a retired key is cleared on every start,
    /// so a mirrored one would be deleted moments after it was published.
    func testNoKeyIsBothMirroredAndRetired() {
        XCTAssertTrue(
            Set(CloudSync.mirroredSettingKeys).isDisjoint(with: Set(CloudSync.retiredSettingKeys)))
    }

    /// The user's name, their About you note and the apps learning skips
    /// follow them. The writing is a file, not a key, so it cannot.
    func testThePersonalSettingsAreMirrored() {
        for key in [TypingPreferences.nameKey, TypingPreferences.aboutKey,
                    TypingHistoryStore.excludedKey] {
            XCTAssertTrue(CloudSync.mirroredSettingKeys.contains(key), key)
        }
    }

    /// Seeded, not live: a Mac copies it once, when the user says they already
    /// use PUSHTYPE elsewhere. A work Mac with learning off is never switched on
    /// by another Mac's choice.
    func testTheLearningSwitchIsSeededNotLive() {
        XCTAssertTrue(CloudSync.seededSettingKeys.contains(TypingHistoryStore.enabledKey))
        XCTAssertFalse(CloudSync.liveSettingKeys.contains(TypingHistoryStore.enabledKey))
    }

    /// Only the person's name and note are applied to a Mac without being asked.
    func testOnlyNameAndAboutAreLive() {
        XCTAssertEqual(Set(CloudSync.liveSettingKeys), [TypingPreferences.nameKey, TypingPreferences.aboutKey])
    }

    /// The wake word switch holds the microphone open and the rest depend on
    /// this Mac's hardware or downloads, so none of them leave it.
    func testPerMacSettingsAreNotPublished() {
        for key in ["wakeWordEnabled", "pillPosition", "inputDevicePriority", "selectedWhisperModel",
                    TypingPreferences.modelKey, TypingPreferences.pauseOnBatteryKey,
                    TypingPreferences.pausedUntilKey, TypingPreferences.clipboardKey,
                    TypingPreferences.screenKey, FeatureSwitches.dictationKey, FeatureSwitches.typeKey,
                    TypingHistoryStore.pausedUntilKey] {
            XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(key), key)
        }
    }

    /// Sharing what Type learned is a per-Mac choice, copied only at setup. The
    /// writing itself travels in its own chunks, never as a mirrored setting.
    func testTheShareSwitchIsSeededAndTheWritingIsNotASetting() {
        XCTAssertTrue(CloudSync.seededSettingKeys.contains(LearnedWritingSync.shareKey))
        XCTAssertFalse(CloudSync.liveSettingKeys.contains(LearnedWritingSync.shareKey))
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains { $0.hasPrefix("sync.history") })
    }

    func testNoKeyIsBothLiveAndSeeded() {
        XCTAssertTrue(Set(CloudSync.liveSettingKeys).isDisjoint(with: Set(CloudSync.seededSettingKeys)))
    }

    /// The Type model is a download, like the speech model.
    func testNothingLearnedOrDownloadedIsMirrored() {
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(TypingPreferences.modelKey))
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains { $0.lowercased().contains("sealed") })
    }

    /// The settings that *should* follow the user are still doing so — this is
    /// the list that would silently shrink if someone edited the wrong line.
    func testTheOrdinarySettingsAreStillMirrored() {
        for key in ["selectedHotkey", "wakeWord", "previewSize"] {
            XCTAssertTrue(CloudSync.mirroredSettingKeys.contains(key), key)
        }
    }
}
