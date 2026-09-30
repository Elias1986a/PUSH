import Foundation

/// The passage to read aloud for every benchmark run.
///
/// Benchmark numbers are only comparable when the input is. The August 2026 figures
/// and the September re-run used different utterances of different lengths, which is
/// why the headline multiple against Wispr moved from 8× to 3.4× without any engine
/// getting slower — the two runs were never measuring the same thing. One fixed script
/// makes the runs a series rather than a pile of anecdotes: same words, same length,
/// same hard parts, so a change in the numbers means a change in the engines.
///
/// It is also chosen to *fail* informatively. Every element below is something the
/// engines demonstrably disagree about, so a run produces an accuracy column and not
/// just a stopwatch. Measured on the first run of it: Ultra emitted `$5 million` in its
/// raw output, Apple Speech emitted `$5000000` and needed our formatter, and Wispr's
/// raw was `five million dollar` until their server rewrote it.
///
/// If you shorten this, keep the list in `exercises` intact — each phrase is load
/// bearing, and dropping one silently removes a column from the comparison.
enum BenchmarkScript {

    /// Bumped whenever `text` changes, and stamped on every live recording, so runs on
    /// different scripts are never averaged together. 1 was the passage without the
    /// quotation (two runs, 2026-09-29); 2 added it; 3 (2026-09-30) is the passage
    /// rewritten for the public page — no named people, nothing a reader could take
    /// as being about them — and adds California mode's casual "like" and a spoken
    /// "new paragraph".
    static let version = 3

    /// How many readings make a published figure. Three was enough to see a spread;
    /// it is not enough to publish a median against someone else's product.
    static let targetRuns = 25

    /// Roughly 25 seconds read at a normal pace. Long enough that per-second rates are
    /// stable, short enough to read 25 times.
    ///
    /// Read the casual "like"s straight through, without a pause: set off by commas
    /// the default filler pass removes them anyway, and California mode would have
    /// nothing to show. "feels like" is a comparison and must survive. The expected
    /// paste is pinned in `Tests/PUSHTests/BenchmarkPassageTests.swift`.
    static let text = """
        Let's move the Q3 planning review to Tuesday, March 3rd at 4:30 PM, since that's \
        like the only slot that works for the Zürich office. Um, we've spent 37% of the \
        $5 million budget, and the new build loads in 15.2 seconds, I mean 1.52 seconds. \
        Everyone who tried it said, quote, it feels like a real improvement, end quote. \
        New paragraph. Could you like send the final numbers before Friday?
        """

    /// What each part of the script is there to expose. Rendered under the script so
    /// the reason for every awkward phrase is visible to whoever is holding the mic.
    static let exercises = [
        "date", "time of day", "percent", "currency", "decimals", "acronym",
        "accented place", "filler word", "self-correction", "casual \u{201C}like\u{201D}",
        "\u{201C}like\u{201D} that stays", "spoken quote", "new paragraph", "question mark"
    ]
}
