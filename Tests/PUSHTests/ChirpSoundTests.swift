import XCTest
@testable import PUSH

/// Every sound in the Settings menu has its file in the app's resources — a
/// missing one would leave a choice that plays nothing.
final class ChirpSoundTests: XCTestCase {
    func testEverySoundHasItsFile() {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PUSH/Resources")
        for sound in ChirpSound.allCases {
            let file = resources.appendingPathComponent("\(sound.fileName).wav")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), sound.displayName)
        }
    }

    @MainActor
    func testDeepTapIsTheDefault() {
        XCTAssertEqual(ChirpSound.allCases.first, .deepTap)
    }
}
