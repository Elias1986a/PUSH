import XCTest
@testable import PUSHCore

/// Streaming shares its folder with the retired offline Unified encoder; each
/// is its own ~600 MB. Deleting one used to delete both. Runs against a
/// temporary folder — never the real models.
final class ParakeetModeFilesTests: XCTestCase {

    private let offline = ParakeetUnifiedFiles.offlineEncoderFile
    private let streaming = ParakeetUnifiedFiles.streamingEncoderFile

    private func makeFolder(_ encoders: [String]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parakeet-modes-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        for name in encoders + ParakeetUnifiedFiles.sharedFiles {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        return dir
    }

    func testEachModeCountsOnlyItsOwnEncoder() throws {
        let dir = try makeFolder([offline])
        XCTAssertTrue(ParakeetUnifiedFiles.hasMode(encoder: offline, in: dir))
        XCTAssertFalse(ParakeetUnifiedFiles.hasMode(encoder: streaming, in: dir),
                       "the offline encoder alone must not make Streaming look downloaded")
    }

    func testDeletingOneModeKeepsTheOther() throws {
        let dir = try makeFolder([offline, streaming])
        try ParakeetUnifiedFiles.deleteMode(encoder: offline, keepingIfPresent: streaming, in: dir)
        XCTAssertFalse(ParakeetUnifiedFiles.hasMode(encoder: offline, in: dir))
        XCTAssertTrue(ParakeetUnifiedFiles.hasMode(encoder: streaming, in: dir))
    }

    /// The launch cleanup frees the retired encoder and never touches Streaming.
    func testRemovingTheRetiredEncoderKeepsStreaming() throws {
        let both = try makeFolder([offline, streaming])
        ParakeetUnifiedFiles.removeRetiredOfflineEncoder(in: both)
        XCTAssertFalse(FileManager.default.fileExists(atPath: both.appendingPathComponent(offline).path))
        XCTAssertTrue(ParakeetUnifiedFiles.hasMode(encoder: streaming, in: both))

        let streamingOnly = try makeFolder([streaming])
        ParakeetUnifiedFiles.removeRetiredOfflineEncoder(in: streamingOnly)
        XCTAssertTrue(ParakeetUnifiedFiles.hasMode(encoder: streaming, in: streamingOnly))
    }

    func testDeletingTheLastModeRemovesTheFolder() throws {
        let dir = try makeFolder([streaming])
        try ParakeetUnifiedFiles.deleteMode(encoder: streaming, keepingIfPresent: offline, in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
