import XCTest
import FluidAudio
@testable import PUSHCore

/// The speech models download from fixed commits, never from `main`.
final class SpeechModelPinsTests: XCTestCase {
    func testEveryPinIsAFullCommitHash() {
        for (repo, revision) in SpeechModelPins.revisions {
            XCTAssertNotNil(revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression), "\(repo): \(revision)")
        }
    }

    /// The repositories FluidAudio uses for the models PUSHTYPE offers: a
    /// renamed or new one here means a model that would download unpinned.
    func testThePinsCoverTheModelsPUSHTYPEOffers() {
        let pinned = Set(SpeechModelPins.revisions.keys)
        for repo in [Repo.parakeetUltra, .parakeetUnified, .nemotronMultilingual, .vad] {
            XCTAssertTrue(pinned.contains(repo.remotePath), repo.remotePath)
        }
    }

    func testApplyingThemOverridesTheRevisionFluidAudioDownloads() {
        let before = ModelRegistry.revisionOverrides
        defer { ModelRegistry.revisionOverrides = before }
        SpeechModelPins.apply()
        for (repo, revision) in SpeechModelPins.revisions {
            XCTAssertEqual(ModelRegistry.revisionOverrides[repo], revision)
        }
    }
}
