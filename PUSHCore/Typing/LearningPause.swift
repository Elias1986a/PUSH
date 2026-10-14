import Foundation

/// "Pause learning": for a while, nothing the user writes is kept.
///
/// Pausing has to cover more than the moment it is pressed. The field being
/// written when the pause ends would otherwise be read in full on the next
/// key, including what was typed during the pause, and kept. So each field
/// seen while paused is remembered and left out for good; writing starts
/// being kept again in the next one.
public struct LearningPause: Equatable, Sendable {
    public var until: Date?
    /// Fields written while paused, newest last.
    public private(set) var skipped: [Int] = []

    /// Few are ever needed: a pause lasts a field or two.
    public static let remembered = 24

    public init(until: Date? = nil) { self.until = until }

    public func isPaused(at now: Date = Date()) -> Bool { until.map { $0 > now } ?? false }

    /// Whether writing in this field may be kept right now.
    public mutating func mayKeep(element: Int, at now: Date = Date()) -> Bool {
        if isPaused(at: now) {
            if !skipped.contains(element) {
                skipped.append(element)
                if skipped.count > Self.remembered { skipped.removeFirst(skipped.count - Self.remembered) }
            }
            return false
        }
        return !skipped.contains(element)
    }
}
