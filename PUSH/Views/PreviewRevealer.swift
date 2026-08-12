import Foundation
import Combine

/// Smooths the live preview's arrival cadence.
///
/// The streaming engine emits a partial roughly once per 1.04s chunk, several
/// words at a time. Rendered as-is that reads as choppy — the line jumps in
/// bursts, and once the text is scrolling the whole thing lurches sideways once
/// a second. This holds the incoming text and reveals it over a few frames, so
/// the line grows (and scrolls) continuously instead.
///
/// Purely cosmetic: it only paces what is already decided. The transcript that
/// gets injected is untouched, and this never shows text the engine hasn't
/// already produced.
@MainActor
final class PreviewRevealer: ObservableObject {

    /// What the pill should draw right now.
    @Published private(set) var revealed: String = ""

    /// How long a freshly-arrived chunk takes to finish appearing. Well under
    /// the ~1.04s between chunks, so the reveal always catches up before the
    /// next one lands and never compounds into extra lag.
    private static let chunkDuration: TimeInterval = 0.4
    /// 120Hz. This display refreshes at up to 120Hz, and stepping at the same
    /// rate halves how far the text jumps per step versus 60. The work per step
    /// is a string prefix and a Text redraw, so the extra ticks are cheap — and
    /// the window is never resized, only the text inside a fixed-width box.
    private static let tick: TimeInterval = 1.0 / 120.0
    private static var ticksPerChunk: Double { chunkDuration / tick }

    private var target: String = ""
    private var timer: Timer?

    /// Point the revealer at the latest partial. Safe to call every partial.
    func setTarget(_ text: String) {
        guard text != target else { return }

        // Cleared between dictations — drop everything immediately rather than
        // animating backwards.
        if text.isEmpty {
            stop()
            target = ""
            revealed = ""
            return
        }

        // Partials are append-only, so the new text normally extends what's on
        // screen. If it doesn't (a reset, or an engine that rewrites), snap
        // rather than trying to animate an edit.
        guard text.hasPrefix(revealed) else {
            stop()
            target = text
            revealed = text
            return
        }

        target = text
        start()
    }

    // MARK: - Private

    private func start() {
        guard timer == nil else { return }   // already catching up
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        // .common so the reveal keeps running during menu tracking and the like.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let remaining = target.count - revealed.count
        guard remaining > 0 else { stop(); return }

        // Spread whatever is left across the remaining budget, so a big chunk
        // reveals faster per frame than a small one and both land in ~400ms.
        let perTick = max(1, Int((Double(remaining) / Self.ticksPerChunk).rounded(.up)))
        revealed = String(target.prefix(revealed.count + perTick))

        if revealed.count >= target.count { stop() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}
