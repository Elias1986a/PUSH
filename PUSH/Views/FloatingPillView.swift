import SwiftUI
import AppKit

struct FloatingPillView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var revealer = PreviewRevealer()
    @State private var dotPhase1: CGFloat = 0
    @State private var dotPhase2: CGFloat = 0
    @State private var dotPhase3: CGFloat = 0

    /// The travelling edge pulse.
    private enum Pulse {
        static let color = Color(red: 0.69, green: 1.0, blue: 0.0)
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

    /// Width the preview reserves, from the chosen size. It is a fixed width,
    /// not a maximum: the pill claims the whole box up front and keeps it, so
    /// the window stops resizing (and re-centering) per word and the text
    /// underneath never gets shoved sideways.
    private var previewWidth: CGFloat { appState.previewSize.width }

    private var previewFontSize: CGFloat { appState.previewSize.fontSize }

    /// Must match `livePreviewText`'s font — it measures the string to decide
    /// whether the text still fits. Condensed: narrower glyphs fit more words
    /// per line, so a size step shows up as height rather than length.
    private var previewFont: NSFont {
        NSFont.systemFont(ofSize: previewFontSize, weight: .medium, width: .condensed)
    }

    private var isTopPlacement: Bool { appState.pillPosition == .top }

    /// The tab's fill is always black, so its content can't follow the system
    /// appearance the way it can on the capsule's material.
    private var contentColor: Color { isTopPlacement ? .white : .primary }

    var body: some View {
        Group {
            if isTopPlacement {
                notchTab
            } else {
                capsulePill
            }
        }
        .foregroundStyle(contentColor)
        .opacity(shouldShow ? 1 : 0)
        .scaleEffect(
            x: isTopPlacement ? 1 : (shouldShow ? 1 : 0.85),
            y: shouldShow ? 1 : (isTopPlacement ? 0.001 : 0.85),
            anchor: isTopPlacement ? .top : .center
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: shouldShow)
        .fixedSize()
        .task {
            // Start animation when view appears and is listening
            if appState.isListening {
                startBouncingAnimation()
            }
        }
        .onChange(of: appState.isListening) { _, isListening in
            if isListening {
                startBouncingAnimation()
            }
        }
        .onChange(of: appState.livePartialText) { _, text in
            revealer.setTarget(text)
        }
    }

    /// The top placement: a black tab hanging off the screen's top edge that
    /// reads as the notch continuing downward. Square on top because that edge
    /// *is* the screen edge, rounded below.
    ///
    /// The housing band is left empty — on a MacBook those points sit behind
    /// the camera, and on every other display behind the menu bar — so the
    /// content starts underneath it. Collapse to zero and the shape retracts
    /// into the housing rather than shrinking in place.
    private var notchTab: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: appState.pillTopInset)

            pillContent
                .padding(.horizontal, 16)
                .padding(.top, 3)
                .padding(.bottom, 7)
        }
        .frame(minWidth: AppState.notchMinimumWidth)
        // No shadow: the tab reads as an extension of the hardware, and
        // hardware doesn't cast one onto the desktop. A shadow only added
        // a band of grey pixels around a shape that should end at its edge.
        // The edge treatment is the pulse below instead — drawn *inside* the
        // silhouette, so it needs no slack around the window either.
        .background(tabShape.fill(.black))
        .overlay(edgePulse)
    }

    private var tabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 16,
            style: .continuous
        )
    }

    /// A two-point acid-green outline with a bright band sweeping across it,
    /// running the three open sides — left flank, bottom, right flank. The top
    /// edge is left bare: it is where the shape meets the screen edge (and, on
    /// a MacBook, emerges from the notch), so an outline across it would draw
    /// a lid on something meant to read as open at the top.
    ///
    /// Inset rather than centred on the path: the window is sized to the shape
    /// exactly, so half of a centred stroke — and all of an outer glow — would
    /// be clipped. The bloom is a blurred copy of the same stroke clipped back
    /// to the silhouette, which reads as a glow while staying inside the frame.
    private var edgePulse: some View {
        Group {
            if reduceMotion {
                // A sweep is motion for its own sake; hold it at a steady outline.
                tabShape.strokeBorder(
                    Pulse.color.opacity(Pulse.peakOpacity * 0.6),
                    lineWidth: Pulse.lineWidth
                )
            } else {
                TimelineView(.animation) { context in
                    let gradient = pulseGradient(at: context.date)
                    ZStack {
                        tabShape
                            .strokeBorder(gradient, lineWidth: Pulse.lineWidth)
                            .blur(radius: 3)
                            .clipShape(tabShape)
                        tabShape
                            .strokeBorder(gradient, lineWidth: Pulse.lineWidth)
                    }
                }
            }
        }
        // Three sides only: left, bottom, right. Masking the top band off the
        // finished stroke keeps the flanks and the bottom corners on exactly
        // the fill's geometry — tracing an open path by hand would have to
        // re-approximate the continuous corner curve and would show a seam
        // against the black. The top run is what gets cut; the flanks simply
        // begin a couple of points down, which is invisible against the
        // screen edge.
        .mask(alignment: .bottom) {
            Rectangle().padding(.top, Pulse.lineWidth + 1)
        }
    }

    /// The outline's colour along its width at this instant. The band travels
    /// from off one edge to off the other, so it enters and leaves rather than
    /// snapping back to the start.
    private func pulseGradient(at date: Date) -> LinearGradient {
        let cycle = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: Pulse.period) / Pulse.period
        // Travels across 1.5 widths, starting a quarter-width off the leading
        // edge, so the band is fully outside the shape at both ends.
        let phase = CGFloat(cycle) * 1.5 - 0.25

        let floor = Pulse.color.opacity(Pulse.floorOpacity)
        let peak = Pulse.color.opacity(Pulse.peakOpacity)
        // Clamped in order: gradient stops have to be non-decreasing.
        let lead = min(max(phase - Pulse.halfWidth, 0), 1)
        let mid = min(max(phase, 0), 1)
        let trail = min(max(phase + Pulse.halfWidth, 0), 1)

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

    /// The original floating capsule, shown at the bottom of the screen.
    private var capsulePill: some View {
        pillContent
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
            )
    }

    /// Icon plus status/preview — identical in both placements.
    private var pillContent: some View {
        HStack(spacing: 6) {
            // Microphone icon
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                // Red means the mic is live, so it follows capture, not the key.
                .foregroundStyle(appState.isCapturing ? .red : .orange)

            if reservesPreviewWidth {
                // Claim the full width up front — including during the ~2s before
                // the first partial lands — so the pill is laid out and centered
                // for the text it is about to hold. Nothing then moves for the
                // rest of the dictation: no widening, no re-centering, and the
                // status label sits exactly where the first word will appear.
                if revealer.revealed.isEmpty {
                    statusLabel
                        .frame(width: previewWidth, alignment: .leading)
                } else {
                    livePreviewText   // carries the same fixed width itself
                }
            } else {
                statusLabel
            }
        }
    }

    /// Status text with animated dots — the pill's original content.
    private var statusLabel: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(baseStatusText)
                .font(.system(size: 11, weight: .medium))

            if appState.isListening {
                bouncingDots
                    .padding(.bottom, 1)  // Align with text baseline
            }
        }
    }

    /// The rough in-flight transcript, laid out in a fixed-width box.
    ///
    /// While the text still fits it is leading-aligned, so each new word lands
    /// to the right of the last and everything already on screen stays exactly
    /// where it was — no motion at all. Only once it outgrows the box does it
    /// flip to trailing, pinning the newest words and scrolling the older ones
    /// off the left under a fade. The fade is applied only when it is actually
    /// scrolling; otherwise it would dim the first word of every dictation.
    private var livePreviewText: some View {
        Text(revealer.revealed)
            .font(.system(size: previewFontSize, weight: .medium))
            .fontWidth(.condensed)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: previewWidth, alignment: previewOverflows ? .trailing : .leading)
            .clipped()
            .mask(
                LinearGradient(
                    stops: previewOverflows
                        ? [.init(color: .clear, location: 0),
                           .init(color: .black, location: 0.06),
                           .init(color: .black, location: 1)]
                        : [.init(color: .black, location: 0),
                           .init(color: .black, location: 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            // Dim once the hotkey is released: what's on screen is the captured
            // text, and cleanup is still to come.
            .opacity(appState.isListening ? 1 : 0.55)
    }

    /// True once the transcript is wider than the box and has to start scrolling.
    private var previewOverflows: Bool {
        (revealer.revealed as NSString)
            .size(withAttributes: [.font: previewFont]).width > previewWidth
    }

    private var bouncingDots: some View {
        HStack(spacing: 1) {
            Circle()
                .fill(contentColor)
                .frame(width: 3, height: 3)
                .offset(y: dotPhase1 * -2)

            Circle()
                .fill(contentColor)
                .frame(width: 3, height: 3)
                .offset(y: dotPhase2 * -2)

            Circle()
                .fill(contentColor)
                .frame(width: 3, height: 3)
                .offset(y: dotPhase3 * -2)
        }
        .padding(.leading, 1)
    }

    private var shouldShow: Bool { appState.pillShouldShow }

    /// Whether to lay the pill out for the preview. Gated on the *active* engine
    /// so the wide box is never reserved for a model that can't stream partials
    /// and would leave it empty.
    private var reservesPreviewWidth: Bool {
        appState.showLivePreview
            && appState.activeModel.engineType == .parakeetStreaming
            && (appState.isListening || appState.isProcessing)
    }

    /// True once there is actual transcript on screen (~2s into a dictation).
    private var showPreview: Bool {
        reservesPreviewWidth && !revealer.revealed.isEmpty
    }

    private var iconName: String {
        if appState.isListening {
            return "mic.fill"
        } else if showPreview {
            // Released, holding the captured text while cleanup runs.
            return "hourglass"
        } else {
            return "mic.fill"
        }
    }

    private var baseStatusText: String {
        if appState.modelUnavailable {
            return "Model unavailable"
        } else if appState.isListening {
            // Only claim to be listening once the microphone is actually
            // capturing. On a cold press the audio device can take seconds to
            // come up, and saying "Listening" through that wait invites the user
            // to talk into nothing — measured at 4.2s, with the whole sentence
            // lost. Recording can still legitimately start before the *model* is
            // ready; that isn't what this covers.
            return appState.isCapturing ? "Listening" : "Warming up..."
        } else if appState.isProcessing {
            return "Processing..."
        } else if !appState.isModelReady {
            return "Loading model..."
        } else if appState.isWarmingUp || appState.isPrewarming {
            // Model is usable, but the capture path (and shaders) are still
            // warming. Shown until a press would actually be fast.
            return "Warming up..."
        } else {
            return ""
        }
    }

    private func startBouncingAnimation() {
        // Reset all phases first
        dotPhase1 = 0
        dotPhase2 = 0
        dotPhase3 = 0

        // Start animations with staggered delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                self.dotPhase1 = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                self.dotPhase2 = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                self.dotPhase3 = 1
            }
        }
    }
}

#if DEBUG
#Preview("Bottom · capsule") {
    FloatingPillView()
        .environmentObject(AppState.shared)
        .padding(50)
        .background(Color.gray.opacity(0.3))
}

/// The top placement, staged against a stand-in screen edge. The real inset is
/// measured per screen at runtime; 37 is a 14" MacBook Pro's notch.
#Preview("Top · notch tab") {
    let state = AppState.shared
    state.pillPosition = .top
    state.pillTopInset = 37
    state.isListening = true
    state.isCapturing = true

    return VStack(spacing: 0) {
        FloatingPillView()
            .environmentObject(state)
        Spacer()
    }
    .frame(width: 900, height: 260)
    .background(
        LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
    )
}
#endif
