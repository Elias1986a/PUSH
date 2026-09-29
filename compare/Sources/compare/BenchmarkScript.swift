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
    /// quotation (two runs, 2026-09-29); 2 added it.
    static let version = 2

    /// Roughly 23 seconds read at a normal pace. Long enough that per-second rates are
    /// stable, short enough to read twice without irritation.
    ///
    /// The quotation is spoken with its markers, "quote … end quote", because that is
    /// what a person dictating says; PUSH should paste `Priya said, "ship it anyway."`.
    static let text = """
        Let's move the Q3 review to Tuesday, March 3rd at 4:30 PM — Larry, Priya and \
        Joe are all in, which puts us at 37% of the $5 million target. Um, latency came \
        back at 15.2 seconds, I mean 1.52 seconds, so ask the Zürich team to re-run it. \
        Priya said, quote, ship it anyway, end quote. Can you confirm before Friday?
        """

    /// What each part of the script is there to expose. Rendered under the script so
    /// the reason for every awkward phrase is visible to whoever is holding the mic.
    static let exercises = [
        "date", "time of day", "percent", "currency", "decimals",
        "acronym", "accented name", "filler word", "self-correction", "spoken quote", "question mark"
    ]
}
