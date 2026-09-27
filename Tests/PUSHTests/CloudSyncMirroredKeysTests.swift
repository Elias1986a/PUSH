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

    /// The settings that *should* follow the user are still doing so — this is
    /// the list that would silently shrink if someone edited the wrong line.
    func testTheOrdinarySettingsAreStillMirrored() {
        for key in ["selectedHotkey", "wakeWord", "wakeWordEnabled", "previewSize"] {
            XCTAssertTrue(CloudSync.mirroredSettingKeys.contains(key), key)
        }
    }
}
