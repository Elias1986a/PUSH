import Foundation

/// Formatting for the provisional transcript shown in the floating pill while
/// the user is still speaking.
///
/// The streaming engine's transcript is append-only and unbounded, but the pill
/// is one line on a fixed-width panel — so only the tail is shown, cut at a word
/// boundary rather than mid-word.
enum LiveTranscript {

    /// Roughly the widest single line the pill can show at 11pt without the
    /// capsule outgrowing its panel.
    static let maxDisplayCharacters = 64

    /// The last `limit` characters of `text`, starting at a word boundary and
    /// prefixed with an ellipsis when anything was dropped. Text shorter than
    /// the limit is returned as-is (whitespace-trimmed).
    static func tail(of text: String, limit: Int = maxDisplayCharacters) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0 else { return "" }
        guard trimmed.count > limit else { return trimmed }

        let window = String(trimmed.suffix(limit))

        // Start on a word boundary so the first visible word is whole. A window
        // that lands inside one very long word has no boundary to find — show
        // the raw tail rather than nothing.
        if let space = window.firstIndex(of: " ") {
            let word = window[window.index(after: space)...]
            if !word.isEmpty {
                return "…" + word
            }
        }
        return "…" + window
    }
}
