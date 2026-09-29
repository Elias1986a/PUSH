import XCTest
@testable import PUSH
@testable import PUSHCore

/// What launch loads when the saved preference and the disk disagree.
///
/// This is the decision behind a real bug: a Nemotron preference reached a
/// second Mac through iCloud, and every launch there spent ~600 MB and several
/// minutes fetching a multilingual model nobody on that machine had chosen —
/// with dictation unavailable throughout. The preference now stops being an
/// instruction to download; it is only an instruction to load.
final class LaunchModelTests: XCTestCase {

    /// The ordinary case: what was chosen is on disk, so it runs.
    func testThePreferenceWinsWhenItCanRun() {
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .nemotronMultilingual,
                                    ready: [.nemotronMultilingual, .parakeetUnified]),
            .nemotronMultilingual)
    }

    /// The bug. Nothing of Nemotron's is on disk, Unified is, so Unified serves
    /// and the 600 MB stays unspent until someone asks for it.
    func testAnUnavailablePreferenceFallsBackToTheDefault() {
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .nemotronMultilingual, ready: [.parakeetUnified]),
            .parakeetUnified)
    }

    /// The default is preferred over the other downloaded models, whatever
    /// order the set happens to iterate in.
    func testTheDefaultIsPreferredOverOtherDownloadedModels() {
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .nemotronMultilingual,
                                    ready: [.parakeetUnified, .parakeetStreaming, .parakeetUltra]),
            WhisperModel.defaultModel)
    }

    /// With the default absent too, the settings list's own order decides.
    func testAmongTheRestTheSettingsOrderDecides() {
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .parakeetUnified,
                                    ready: [.nemotronMultilingual, .parakeetStreaming]),
            .parakeetStreaming)
    }

    /// A first launch has nothing to fall back on, and the one download nobody
    /// asked for that is still right is the one that makes the app exist.
    func testAFreshInstallStillDownloadsWhatWasChosen() {
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .nemotronMultilingual, ready: []),
            .nemotronMultilingual)
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .parakeetUnified, ready: []),
            .parakeetUnified)
    }

    /// Apple Speech was removed in 8.2.0. A saved or synced "apple-speech"
    /// must not decode into anything, so `AppState` keeps the default.
    func testTheRemovedAppleSpeechPreferenceDecodesToNothing() {
        XCTAssertNil(WhisperModel(rawValue: "apple-speech"))
    }
}
