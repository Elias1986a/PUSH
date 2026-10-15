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
        SpeechModelPins.apply(modelsDirectory: temporaryModels())
        for (repo, revision) in SpeechModelPins.revisions {
            XCTAssertEqual(ModelRegistry.revisionOverrides[repo], revision)
        }
    }

    private func temporaryModels() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pins-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func marker(_ repo: Repo, in dir: URL) -> String? {
        let url = dir.appendingPathComponent(repo.folderName)
            .appendingPathComponent(SpeechModelPins.revisionMarker)
        return (try? String(contentsOf: url, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A model downloaded before the pins has no marker; FluidAudio would
    /// delete it and download it again at launch unless it is marked.
    func testAnUnmarkedDownloadIsKeptAsThePinnedVersion() throws {
        let dir = temporaryModels()
        let folder = dir.appendingPathComponent(Repo.parakeetUnified.folderName)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("parakeet_unified_decoder.mlmodelc"),
            withIntermediateDirectories: true)
        SpeechModelPins.adoptExistingDownloads(in: dir)
        XCTAssertEqual(marker(.parakeetUnified, in: dir),
                       SpeechModelPins.revisions[Repo.parakeetUnified.remotePath])
    }

    func testAnExistingMarkerIsLeftAlone() throws {
        let dir = temporaryModels()
        let folder = dir.appendingPathComponent(Repo.parakeetUltra.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "older\n".write(to: folder.appendingPathComponent(SpeechModelPins.revisionMarker),
                            atomically: true, encoding: .utf8)
        SpeechModelPins.adoptExistingDownloads(in: dir)
        XCTAssertEqual(marker(.parakeetUltra, in: dir), "older")
    }

    func testNothingIsMarkedWhereNothingWasDownloaded() throws {
        let dir = temporaryModels()
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(Repo.vad.folderName), withIntermediateDirectories: true)
        SpeechModelPins.adoptExistingDownloads(in: dir)
        XCTAssertNil(marker(.vad, in: dir))
        XCTAssertNil(marker(.parakeetUltra, in: dir))
    }
}
