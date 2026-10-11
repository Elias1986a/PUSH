import XCTest
@testable import PUSHCore

final class TypingModelCatalogTests: XCTestCase {
    func testThreeTiersInOrderWithRecommendedAsDefault() {
        XCTAssertEqual(TypingModel.allCases, [.lite, .recommended, .best])
        XCTAssertEqual(TypingModel.defaultModel, .recommended)
    }

    func testEveryEntryIsComplete() {
        for model in TypingModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty, "\(model)")
            XCTAssertTrue(model.repo.contains("/"), "\(model)")
            XCTAssertTrue(model.file.hasSuffix(".gguf"), "\(model)")
            XCTAssertGreaterThan(model.bytes, 100_000_000, "\(model)")
            XCTAssertEqual(model.licence, "Apache-2.0", "\(model)")
            XCTAssertEqual(model.sha256.count, 64, "\(model)")
            XCTAssertTrue(model.sha256.allSatisfy(\.isHexDigit), "\(model)")
        }
    }

    func testURLsArePinnedToARevisionNotABranch() {
        for model in TypingModel.allCases {
            XCTAssertEqual(model.revision.count, 40, "\(model)")
            let url = model.downloadURL.absoluteString
            XCTAssertTrue(url.hasPrefix("https://huggingface.co/\(model.repo)/resolve/\(model.revision)/"), url)
            XCTAssertFalse(url.contains("/resolve/main/"), url)
            XCTAssertTrue(url.hasSuffix(model.file), url)
        }
    }

    func testMaxLengthPresetsFromThePhase0Eval() {
        XCTAssertEqual(TypingModel.lite.maxLength, .short)
        XCTAssertEqual(TypingModel.recommended.maxLength, .medium)
        XCTAssertEqual(TypingModel.best.maxLength, .long)
    }

    func testLengthPresetsAndClamping() {
        XCTAssertEqual(LengthPreset.allCases.map(\.words), [1...3, 4...7, 8...12, 12...20])
        XCTAssertEqual(LengthPreset.defaultPreset, .short)
        XCTAssertEqual(LengthPreset.long.clamped(to: .lite), .short)
        XCTAssertEqual(LengthPreset.tiny.clamped(to: .lite), .tiny)
        XCTAssertEqual(LengthPreset.long.clamped(to: .best), .long)
        XCTAssertEqual(LengthPreset.offered(for: .recommended), [.tiny, .short, .medium])
    }

    func testIDsAreStableStrings() {
        // Persisted as the user's choice; renaming one would orphan a download.
        XCTAssertEqual(TypingModel.allCases.map(\.rawValue),
                       ["qwen3.5-0.8b-base", "qwen3.5-2b-base", "gemma4-e2b-base"])
    }
}
