import Foundation
import os
import PUSHCore

/// Millisecond timing for the hotkey-press → recording path.
///
/// PushLogger stamps whole seconds, which can't resolve where the gap between
/// a key press and `AudioRecorder: Started recording` actually goes. Every mark
/// is reported as an offset from the key-down, so one dictation prints a
/// readable breakdown of the path.
///
/// Kept in the shipping build on purpose: the gap only reproduces on a real
/// first press after a real launch, which is not something a synthetic harness
/// can stage — synthesized modifier events are ignored by the CGEvent tap.
@MainActor
enum PressTiming {
    private static var start: Date?

    static func begin() {
        start = Date()
    }

    static func mark(_ label: String) {
        guard let start else { return }
        let ms = Date().timeIntervalSince(start) * 1000
        PushLogger.log(String(format: "PressTiming: %@ +%.0fms", label, ms))
    }

    /// Stop reporting until the next press, so marks from the recording path
    /// don't keep firing against a stale start.
    static func end() {
        start = nil
    }
}

/// Millisecond timing for the key-release → paste path, the latency the user
/// feels after they stop talking. Same idea as `PressTiming`, but marked from
/// the pipeline's background work too, so the start is behind a lock.
enum ReleaseTiming {
    private static let start = OSAllocatedUnfairLock<Date?>(initialState: nil)

    static func begin() {
        start.withLock { $0 = Date() }
    }

    static func mark(_ label: String) {
        guard let start = start.withLock({ $0 }) else { return }
        let ms = Date().timeIntervalSince(start) * 1000
        PushLogger.log(String(format: "ReleaseTiming: %@ +%.0fms", label, ms))
    }

    static func end() {
        start.withLock { $0 = nil }
    }
}
