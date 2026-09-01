import Foundation

/// A scroll position that will not go backwards on its own.
///
/// Prediction runs ahead of the last confirmed match, so when the next partial
/// lands it often lands *behind* where the display had reached. Following that
/// literally makes the text rise and then fall back — a visible bounce, once
/// per partial. Reading against text that moves backwards is worse than reading
/// against text that is slightly late.
///
/// So small backward corrections hold instead of rewinding. A large one is a
/// different thing entirely — the reader went back to re-read, or pressed the
/// up arrow — and that must be followed, or the prompter would refuse to go
/// where it is told.
public struct ForwardOnlyPosition: Sendable {

    /// How far back the target may fall before it is believed, in lines.
    ///
    /// Above the jitter that prediction produces, below a deliberate move. A
    /// prediction that ran two tokens ahead lands well inside a line; a reader
    /// going back to re-read lands a line or more behind.
    public var tolerance: Double

    public private(set) var value: Double

    public init(tolerance: Double = 0.75, value: Double = 0) {
        self.tolerance = tolerance
        self.value = value
    }

    /// Take a freshly computed target and return the position to actually use.
    @discardableResult
    public mutating func advance(to target: Double) -> Double {
        if target < value - tolerance {
            // Far enough back to be meant.
            value = target
        } else {
            value = max(value, target)
        }
        return value
    }

    /// Jump to a position outright — a new take, or the reader saying where
    /// they are. Not subject to the ratchet: this *is* the correction.
    public mutating func reset(to target: Double) {
        value = target
    }
}
