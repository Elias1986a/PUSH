import XCTest
@testable import PUSHCore

/// The compare tool's benchmark passage (`compare/…/BenchmarkScript.swift`, v3), as
/// Parakeet Ultra writes it raw, through the chain the app runs: self-corrections,
/// then California mode, then formatting. Pinned because the passage is published on
/// the website — a pipeline change that breaks it should fail here, not surface as a
/// wrong row in the next benchmark.
final class BenchmarkPassageTests: XCTestCase {

    private let raw = "Let's move the Q3 planning review to Tuesday, March 3rd at 4.30 p.m., "
        + "since that's like the only slot that works for the Zurich office. "
        + "Um, we've spent 37% of the $5 million budget, and the new build loads in "
        + "15.2 seconds, I mean 1.52 seconds. "
        + "Everyone who tried it said, quote, it feels like a real improvement, end quote. "
        + "Could you send me like the final numbers before Friday"

    private func paste(california: Bool) -> String {
        let corrected = TranscriptionPipeline.resolveSelfCorrections(raw)
        let casual = california ? TranscriptionPipeline.removeCasualLike(corrected) : corrected
        return TranscriptionPipeline.postProcess(casual, hasNativePunctuation: true)
    }

    func testPassageWithTheBenchmarkDefaults() {
        XCTAssertEqual(paste(california: true),
            "Let's move the Q3 planning review to Tuesday, March 3rd at 4:30 p.m., "
            + "since that's the only slot that works for the Zurich office. "
            + "We've spent 37% of the $5 million budget, and the new build loads in 1.52 seconds. "
            + "Everyone who tried it said, \"It feels like a real improvement.\" "
            + "Could you send me the final numbers before Friday?")
    }

    /// Both casual "like"s are ones only California mode removes; "feels like"
    /// is a comparison and stays either way.
    func testCaliforniaModeIsWhatRemovesTheCasualLikes() {
        let off = paste(california: false)
        XCTAssertTrue(off.contains("that's like the only slot"))
        XCTAssertTrue(off.contains("send me like the final"))
        XCTAssertTrue(off.contains("feels like a real improvement"))
    }
}
