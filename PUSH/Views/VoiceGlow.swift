import SwiftUI
import Foundation

/// A sound-reactive glow inside the dictation pill: seven coloured lobes that
/// rise from its bottom edge with your voice, clipped to its silhouette.
///
/// Inside only. The library also draws a halo spilling out below the pill and
/// paints colour into its edge; on a pill this small both read as the effect
/// leaking out of the shape, so neither is drawn.
///
/// A port of `voice-glow`, whose `pill` preset is tuned for "a ~150×44
/// recording pill" — near enough our own. The lobe table, palette and layer
/// multipliers are that library's tuned numbers; everything else is rebuilt on
/// `Canvas`, because the original is CSS radial-gradients, `mask-composite`
/// and SVG filters and none of that crosses to AppKit.
///
///     voice-glow — Copyright (c) 2026 Jakub Antalik
///     Licensed under the MIT License.
///     https://github.com/Jakubantalik/Libraries.dev
///
/// Deliberately *not* used by the teleprompter. `HotkeyManager` makes a press
/// during a take stop the prompter instead of starting dictation, so the two
/// can never be live together — but the prompter also draws its own tab, and
/// it wears `NotchEdgePulse` rather than this. Keeping the glow here means
/// that stays true without a flag anyone has to remember.
struct VoiceGlow: View {
    /// The pill's silhouette. The glow is clipped to it.
    var shape: AnyShape
    /// Whether a dictation is live. Drives the whole effect's fade in and out.
    var isActive: Bool

    @ObservedObject private var audioLevel = AudioLevelMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Tuning {
        /// Everything below is authored against the library's ~350px chat
        /// input; the pill preset shrinks the whole effect by this.
        static let scale: CGFloat = 0.45

        /// Resting glow while a dictation is live but nothing is being said,
        /// so the pill never looks dead mid-sentence.
        static let idle: Double = 0.18
        /// How tall the lobes grow at full level, over the idle height.
        static let reach: Double = 1.35

        /// Width and height multipliers on the lobe table, and the alpha.
        /// Not the library's inner-light numbers (0.855, 0.855, 0.46): that
        /// layer was a tint under a bright halo, and on its own inside the pill
        /// it barely cleared the bottom edge. These sit between its inner light
        /// and its bloom, so speech lights the pill most of the way up.
        static let widthScale: CGFloat = 1.2
        static let heightScale: CGFloat = 2.0
        static let alpha: Double = 0.95

        /// `glowWidth` / `glowHeight` from the pill preset.
        static let glowWidth: CGFloat = 0.65
        static let glowHeight: CGFloat = 0.95

        /// Horizontally the glow is fitted to the pill rather than a fixed
        /// size, so it runs edge to edge on the wide notch tab as well as the
        /// capsule: this many lobe-table units span centre to edge. The
        /// outermost lobes sit at 108, just inside it.
        static let halfSpan: CGFloat = 120

        /// The ellipse every lobe is masked to, so the glow reads as one beam
        /// rather than seven separate blobs. Its width is the pill's, times
        /// this; its height is in the library's unscaled px.
        static let rangeWidth: CGFloat = 0.65
        static let rangeHeight: CGFloat = 130

        /// Where each lobe's gradient has faded out, as a fraction of its
        /// radius: `clamp(70 * softness, 40, 95)` at the pill's softness.
        static let lobeFade: Double = 0.62

        static let blur: CGFloat = 3

        /// The pill preset runs hotter than the chat input to carry on a dark
        /// chip: `voiceTypeStyle.pill`.
        static let brightness: Double = 1.35
        static let saturation: Double = 1.5

        /// Seconds the whole effect takes to fade in and out with `isActive`.
        static let fade: Double = 0.28
    }

    var body: some View {
        // Mounted only while dictating, not merely hidden: `TimelineView`
        // redraws on every display refresh for as long as it is in the
        // hierarchy, and the pill stays mounted the whole time the app is
        // running. An invisible glow driving a 60Hz canvas is battery an
        // offline dictation app has no excuse for spending.
        ZStack {
            if isActive {
                glow
                    .brightness(Tuning.brightness - 1)
                    .saturation(Tuning.saturation)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Tuning.fade), value: isActive)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var glow: some View {
        if reduceMotion {
            // A glow that breathes with a voice is motion for its own sake to
            // anyone who asked for less of it. Hold it at rest.
            layers(levels: [Tuning.idle, Tuning.idle, Tuning.idle])
        } else {
            TimelineView(.animation) { context in
                layers(levels: BandEnvelopes.shared.advance(
                    to: context.date,
                    target: audioLevel.level
                ))
            }
        }
    }

    private func layers(levels: [Double]) -> some View {
        lobeField(levels: levels)
            .blur(radius: Tuning.blur)
            .clipShape(shape)
    }

    // MARK: The lobes

    /// Seven ellipses along the pill's bottom edge, each its own colour and
    /// each rising with the band it follows, clipped to one centred ellipse.
    private func lobeField(levels: [Double]) -> some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height)
            // Points per lobe-table unit across the pill.
            let unitX = size.width / 2 / Tuning.halfSpan

            // The mask first: `clipToLayer` takes the alpha of what it draws
            // as the clip, so everything after is confined to the beam's
            // ellipse and fades out at its rim instead of ending on an edge.
            context.clipToLayer { mask in
                let peak = levels.max() ?? 0
                let grow = 1 + peak * 0.35
                ellipse(
                    in: &mask,
                    centre: centre,
                    radius: CGSize(
                        width: size.width * Tuning.rangeWidth * grow,
                        height: Tuning.rangeHeight * Tuning.scale * grow
                    ),
                    gradient: Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.5),
                        .init(color: .clear, location: 1)
                    ])
                )
            }

            // Additive: two lobes overlapping should read as more light, not
            // as the nearer one covering the further.
            context.blendMode = .plusLighter

            for (index, lobe) in Self.lobes.enumerated() {
                let colour = Self.palette[index].opacity(Tuning.alpha)
                let rise = levels[lobe.band]

                ellipse(
                    in: &context,
                    centre: CGPoint(
                        x: centre.x + lobe.x * unitX,
                        y: centre.y
                    ),
                    radius: CGSize(
                        width: lobe.width * Tuning.widthScale * Tuning.glowWidth * unitX,
                        height: lobe.height * Tuning.heightScale * Tuning.glowHeight * Tuning.scale
                            * CGFloat(Tuning.idle + rise * Tuning.reach)
                    ),
                    gradient: Gradient(stops: [
                        .init(color: colour, location: 0),
                        .init(color: colour.opacity(0), location: Tuning.lobeFade)
                    ])
                )
            }
        }
    }

    /// One lobe. `GraphicsContext`'s radial gradient is circular, so the
    /// ellipse comes from drawing a circle into a scaled layer.
    private func ellipse(
        in context: inout GraphicsContext,
        centre: CGPoint,
        radius: CGSize,
        gradient: Gradient
    ) {
        guard radius.width > 0, radius.height > 0 else { return }
        let unit: CGFloat = 100
        context.drawLayer { layer in
            layer.translateBy(x: centre.x, y: centre.y)
            layer.scaleBy(x: radius.width / unit, y: radius.height / unit)
            layer.fill(
                Path(ellipseIn: CGRect(x: -unit, y: -unit, width: unit * 2, height: unit * 2)),
                with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: unit)
            )
        }
    }

    // MARK: The tuned tables

    /// Lobe geometry: offset from centre, radii, and which band drives it.
    /// Centre first, then pairs outward.
    private struct Lobe {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
        var band: Int
    }

    private static let lobes: [Lobe] = [
        Lobe(x: 0, width: 74, height: 46, band: 0),
        Lobe(x: -36, width: 54, height: 40, band: 1),
        Lobe(x: 36, width: 54, height: 40, band: 1),
        Lobe(x: -72, width: 48, height: 32, band: 2),
        Lobe(x: 72, width: 48, height: 32, band: 2),
        Lobe(x: -108, width: 42, height: 26, band: 1),
        Lobe(x: 108, width: 42, height: 26, band: 1)
    ]

    /// The `colorful` palette on dark, one colour per lobe.
    private static let palette: [Color] = [
        Color(red: 1.000, green: 0.275, blue: 0.471),
        Color(red: 0.235, green: 0.745, blue: 1.000),
        Color(red: 0.686, green: 0.275, blue: 1.000),
        Color(red: 0.235, green: 0.863, blue: 0.510),
        Color(red: 1.000, green: 0.588, blue: 0.157),
        Color(red: 0.353, green: 0.392, blue: 1.000),
        Color(red: 0.157, green: 0.784, blue: 0.745)
    ]
}

// MARK: - Bands

/// Three envelope followers over the one level we have.
///
/// The original splits an FFT into low / mid / high so a voice makes the
/// colours ripple outward rather than one blob pumping. `AudioLevelMonitor`
/// publishes a single scalar at ~12Hz, so the bands are synthesised the way
/// the library synthesises them when driven by a plain `level`: same input,
/// different time constants, so the lobes diverge on their own — the lows lag
/// and hang on, the highs snap. No noise needed to fake it.
///
/// Shared, so the envelope survives the glow being unmounted between
/// dictations; `advance` resets it after a gap rather than resuming stale.
@MainActor
private final class BandEnvelopes {
    static let shared = BandEnvelopes()

    private var values: [Double] = [0, 0, 0]
    private var lastTick: Date?

    /// Attack and release per band, seconds.
    private static let response: [(attack: Double, release: Double)] = [
        (0.08, 0.34),
        (0.05, 0.22),
        (0.03, 0.14)
    ]

    func advance(to date: Date, target: Double) -> [Double] {
        // A repeat call within one frame must not advance the envelope twice.
        guard date != lastTick else { return values }
        defer { lastTick = date }

        let elapsed = lastTick.map { date.timeIntervalSince($0) } ?? .infinity

        // A gap means this glow was not on screen — the first frame of a
        // dictation, or the one after the pill was ordered out. Start from the
        // level rather than crawling up from whatever the last dictation left
        // behind, which arrives as a visible lurch a beat after you speak.
        guard elapsed <= 0.5 else {
            values = [Double](repeating: target, count: values.count)
            return values
        }

        let step = max(elapsed, 0)
        for band in values.indices {
            let curve = Self.response[band]
            let tau = target > values[band] ? curve.attack : curve.release
            values[band] += (target - values[band]) * (tau <= 0 ? 1 : 1 - exp(-step / tau))
        }
        return values
    }
}

// MARK: - Attaching it

extension View {
    /// Lights the pill from inside. Apply it *before* the pill's fill, so
    /// the glow sits between the fill and the content rather than over the
    /// text — and a background never changes the layout or the window size.
    func voiceGlow(shape: AnyShape, isActive: Bool) -> some View {
        background { VoiceGlow(shape: shape, isActive: isActive) }
    }
}
