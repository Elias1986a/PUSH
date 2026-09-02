import Foundation

/// A scroll position that will not go backwards on its own.
///
/// Prediction runs ahead of the last confirmed match, so when the next partial
/// lands it often lands *behind* where the display had reached. Following that
/// literally makes the text rise and then fall back — a visible bounce, once
/// per partial. Reading against text that moves backwards is worse than reading
/// against text that is slightly late.
///
/// So it never goes backwards at all. There is no tolerance below which a
/// retreat is believed: a tolerance was tried, and prediction being *withdrawn*
/// — when tracking lapses to adrift, the lead vanishes and the target drops by
/// however far it had run ahead — produced a fall bigger than any threshold set
/// for jitter. The text rewound a line and a half.
///
/// Going back happens through `reset` instead, which is what the arrow keys and
/// a new take use. That is the honest distinction: matching never moves
/// backwards, and a reader saying where they are is not matching.
public struct ForwardOnlyPosition: Sendable {

    public private(set) var value: Double

    public init(value: Double = 0) {
        self.value = value
    }

    /// Take a freshly computed target and return the position to actually use.
    @discardableResult
    public mutating func advance(to target: Double) -> Double {
        value = max(value, target)
        return value
    }

    /// Jump to a position outright — a new take, or the reader saying where
    /// they are. Not subject to the ratchet: this *is* the correction.
    public mutating func reset(to target: Double) {
        value = target
    }
}
