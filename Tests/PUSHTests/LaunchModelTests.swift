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
                                    ready: [.parakeetV2, .parakeetStreaming, .parakeetUnified]),
            .parakeetUnified)
    }

    /// With the default absent too, the settings list's own order decides —
    /// which puts Apple Speech last. It needs no download, so it would always
    /// win a "cheapest first" rule, and quietly demoting a Mac to the OS engine
    /// when a Parakeet build is sitting right there is not what anyone meant.
    func testAmongTheRestTheSettingsOrderDecides() {
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .nemotronMultilingual,
                                    ready: [.appleSpeech, .parakeetV2, .parakeetStreaming]),
            .parakeetStreaming)
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .nemotronMultilingual,
                                    ready: [.appleSpeech, .parakeetV2]),
            .parakeetV2)
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

    /// A preference this Mac cannot run at all — `apple-speech` synced from a
    /// macOS 26 machine to one on macOS 15 — is not a download instruction
    /// either. Loading it could only ever throw `requiresNewerSystem`.
    func testAPreferenceThisMacCannotRunFallsBackToTheDefault() throws {
        try XCTSkipIf(WhisperModel.selectable.contains(.appleSpeech),
                      "Apple Speech is selectable on this OS, so it is not the unrunnable case")
        XCTAssertEqual(
            ModelLoader.launchModel(preferred: .appleSpeech, ready: []),
            .parakeetUnified)
    }
}
