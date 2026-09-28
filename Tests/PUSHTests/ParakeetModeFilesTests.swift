import XCTest
@testable import PUSHCore

/// Parakeet Unified and Streaming share one folder but each has its own
/// ~600 MB encoder. Deleting one used to delete both. Runs against a temporary
/// folder — never the real models.
final class ParakeetModeFilesTests: XCTestCase {

    private let offline = ParakeetUnifiedEngine.offlineEncoderFile
    private let streaming = ParakeetUnifiedEngine.streamingEncoderFile

    private func makeFolder(_ encoders: [String]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parakeet-modes-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        for name in encoders + ParakeetUnifiedEngine.sharedFiles {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        return dir
    }

    func testEachModeCountsOnlyItsOwnEncoder() throws {
        let dir = try makeFolder([offline])
        XCTAssertTrue(ParakeetUnifiedEngine.hasMode(encoder: offline, in: dir))
        XCTAssertFalse(ParakeetUnifiedEngine.hasMode(encoder: streaming, in: dir),
                       "the offline encoder alone must not make Streaming look downloaded")
    }

    func testDeletingOneModeKeepsTheOther() throws {
        let dir = try makeFolder([offline, streaming])
        try ParakeetUnifiedEngine.deleteMode(encoder: offline, keepingIfPresent: streaming, in: dir)
        XCTAssertFalse(ParakeetUnifiedEngine.hasMode(encoder: offline, in: dir))
        XCTAssertTrue(ParakeetUnifiedEngine.hasMode(encoder: streaming, in: dir))
    }

    func testDeletingTheLastModeRemovesTheFolder() throws {
        let dir = try makeFolder([streaming])
        try ParakeetUnifiedEngine.deleteMode(encoder: streaming, keepingIfPresent: offline, in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
