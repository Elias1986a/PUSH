import SwiftUI

/// The acid-green outline with a bright band sweeping across it, drawn inside a
/// notch tab's silhouette along its three open sides.
///
/// Extracted from `FloatingPillView` so the teleprompter can wear the same
/// treatment rather than a second copy of it. The colour is a parameter because
/// the prompter says something with it that dictation doesn't — green while it
/// is following your voice, amber once it is guessing.
struct NotchEdgePulse: View {
    /// The shape to trace. Must be the same one filling the tab, so the stroke
    /// sits exactly on the fill's geometry.
    var shape: UnevenRoundedRectangle
    var color: Color = Tuning.defaultColor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Tuning {
        static let defaultColor = Color(red: 0.69, green: 1.0, blue: 0.0)
        /// Seconds for one crossing. Slow enough to read as a sweep rather
        /// than a blink, at the edge of what still looks deliberate.
        static let period: TimeInterval = 3.2
        /// How much of the width the bright band covers, either side of centre.
        static let halfWidth: CGFloat = 0.22
        static let lineWidth: CGFloat = 2
        /// The edge is never fully dark: the sweep rides on a dim constant so
        /// the outline stays legible as an outline between passes.
        static let floorOpacity: Double = 0.16
        static let peakOpacity: Double = 0.95
    }

    var body: some View {
        if reduceMotion {
            // A sweep is motion for its own sake; hold it at a steady outline.
            openEdgeStroke(color.opacity(Tuning.peakOpacity * 0.6))
        } else {
            TimelineView(.animation) { context in
                let gradient = pulseGradient(at: context.date)
                ZStack {
                    // Trimmed before it is blurred, and trimmed again after.
                    // Blurring the full outline first spreads the top run
                    // downward past the trim line, which leaves a faint green
                    // bar across the top — dimmer than the stroke it came
                    // from, but exactly the line the trim exists to remove.
                    // The second trim catches the flanks' bloom reaching back
                    // up into the same band.
                    openEdgeStroke(gradient)
                        .blur(radius: 3)
                        .clipShape(shape)
                        .mask(alignment: .bottom) { openEdgeMask }
                    openEdgeStroke(gradient)
                }
            }
        }
    }

    /// The outline with its top run cut off, leaving the three open sides.
    ///
    /// Trimmed from the finished stroke rather than traced as an open path:
    /// this keeps the flanks and bottom corners on exactly the fill's
    /// geometry, where a hand-built path would have to re-approximate the
    /// continuous corner curve and would show a seam against the black.
    private func openEdgeStroke(_ style: some ShapeStyle) -> some View {
        shape
            .strokeBorder(style, lineWidth: Tuning.lineWidth)
            .mask(alignment: .bottom) { openEdgeMask }
    }

    private var openEdgeMask: some View {
        Rectangle().padding(.top, Tuning.lineWidth + 1)
    }

    /// The outline's colour along its width at this instant. The band travels
    /// from off one edge to off the other, so it enters and leaves rather than
    /// snapping back to the start.
    private func pulseGradient(at date: Date) -> LinearGradient {
        let cycle = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: Tuning.period) / Tuning.period
        // Travels across 1.5 widths, starting a quarter-width off the leading
        // edge, so the band is fully outside the shape at both ends.
        let phase = CGFloat(cycle) * 1.5 - 0.25

        let floor = color.opacity(Tuning.floorOpacity)
        let peak = color.opacity(Tuning.peakOpacity)
        // Clamped in order: gradient stops have to be non-decreasing.
        let lead = min(max(phase - Tuning.halfWidth, 0), 1)
        let mid = min(max(phase, 0), 1)
        let trail = min(max(phase + Tuning.halfWidth, 0), 1)

        return LinearGradient(
            stops: [
                .init(color: floor, location: 0),
                .init(color: floor, location: lead),
                .init(color: peak, location: mid),
                .init(color: floor, location: trail),
                .init(color: floor, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
