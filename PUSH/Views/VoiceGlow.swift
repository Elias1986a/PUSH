import SwiftUI
import Foundation

/// A sound-reactive glow along the bottom edge of the dictation pill: seven
/// coloured lobes that rise and bloom with your voice, drawn in three layers —
/// a blurred halo below the pill, a soft light inside it, and colour painted
/// into its edge.
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
    /// Which side of the pill this instance draws.
    ///
    /// Two views rather than one: the halo has to sit *under* the pill so the
    /// black fill masks its top half — that is what makes it read as light
    /// escaping from beneath an opaque object instead of a colour wash over
    /// it — while the light and the edge belong on top. Wrapping the pill in
    /// one view would put its whole subtree inside a 60Hz `TimelineView`, and
    /// re-laying out the live transcript every frame is not worth it.
    enum Role {
        /// The blurred bloom, drawn behind the pill.
        case halo
        /// The inner light and the edge stroke, drawn in front of it.
        case surface
    }

    var role: Role
    /// The pill's silhouette. The inner light is clipped to it, the stroke
    /// traces it.
    var shape: AnyShape
    /// Whether a dictation is live. Drives the whole effect's fade in and out.
    var isActive: Bool

    @ObservedObject private var audioLevel = AudioLevelMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Tuning {
        /// Everything below is authored against the library's ~350px chat
        /// input; the pill preset shrinks the whole effect by this.
        static let scale: CGFloat = 0.45

        /// Transparent room reserved *below* the pill for the halo to bloom
        /// into. It has to be real layout — an overlay drawn past the pill's
        /// bounds would be cut off by the window edge, which is sized to the
        /// content (see `AppDelegate.setupFloatingPillWindow`).
        static let reservedHeight: CGFloat = 72
        /// The same, either side, for the outermost lobes.
        static let horizontalBleed: CGFloat = 28

        /// Resting glow while a dictation is live but nothing is being said,
        /// so the pill never looks dead mid-sentence.
        static let idle: Double = 0.18
        /// How tall the lobes grow at full level, over the idle height.
        static let reach: Double = 1.35

        /// Per-layer geometry, from the library's three calls to
        /// `lobeGradients`: width and height multipliers on the lobe table,
        /// the layer's alpha, and how far the lobe centre sits below the edge.
        static let strokeLayer = Layer(widthScale: 1.25, heightScale: 1.25, alpha: 1.0, dropBelowEdge: 2)
        static let innerLayer = Layer(widthScale: 0.855, heightScale: 0.855, alpha: 0.46, dropBelowEdge: 0)
        static let bloomLayer = Layer(widthScale: 1.2075, heightScale: 3.5438, alpha: 0.9, dropBelowEdge: 0)

        /// `glowWidth` / `glowHeight` / `lobeSpacing` from the pill preset.
        static let glowWidth: CGFloat = 0.65
        static let glowHeight: CGFloat = 0.95
        static let lobeSpacing: CGFloat = 0.45

        /// The ellipse every layer is masked to, so the glow reads as one
        /// centred beam rather than seven separate blobs. Radii in the
        /// library's unscaled px, after `rangeWidth` / `rangeHeight`.
        static let rangeRadius = CGSize(width: 200 * 0.8, height: 130 * 0.7)

        /// Where each lobe's gradient has faded out, as a fraction of its
        /// radius: `clamp(70 * softness, 40, 95)` at the pill's softness.
        static let lobeFade: Double = 0.62

        /// Blur on the halo layer, and the much lighter touch inside the pill.
        static let bloomBlur: CGFloat = 9.5 * 0.95
        static let innerBlur: CGFloat = 3
        static let edgeLineWidth: CGFloat = 1.5

        /// The pill preset runs hotter than the chat input to carry on a dark
        /// chip: `voiceTypeStyle.pill`.
        static let brightness: Double = 1.35
        static let saturation: Double = 1.5

        /// Seconds the whole effect takes to fade in and out with `isActive`.
        static let fade: Double = 0.28
    }

    struct Layer {
        var widthScale: CGFloat
        var heightScale: CGFloat
        var alpha: Double
        var dropBelowEdge: CGFloat
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

    @ViewBuilder
    private func layers(levels: [Double]) -> some View {
        switch role {
        case .halo:
            lobeField(layer: Tuning.bloomLayer, levels: levels)
                .blur(radius: Tuning.bloomBlur * Tuning.scale)

        case .surface:
            ZStack {
                lobeField(layer: Tuning.innerLayer, levels: levels)
                    .blur(radius: Tuning.innerBlur)
                    .mask { pillSilhouette { shape.fill(.white) } }

                lobeField(layer: Tuning.strokeLayer, levels: levels)
                    .mask { pillSilhouette { shape.stroke(.white, lineWidth: Tuning.edgeLineWidth) } }
            }
        }
    }

    /// Places a mask over just the pill's part of the padded frame — the
    /// reserved halo room below it, and the bleed either side, are not pill.
    private func pillSilhouette<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        VStack(spacing: 0) {
            mask()
            Color.clear.frame(height: Tuning.reservedHeight)
        }
        .padding(.horizontal, Tuning.horizontalBleed)
    }

    // MARK: The lobes

    /// Seven ellipses along the pill's bottom edge, each its own colour and
    /// each rising with the band it follows, clipped to one centred ellipse.
    private func lobeField(layer: Layer, levels: [Double]) -> some View {
        Canvas { context, size in
            let edgeY = size.height - Tuning.reservedHeight
            let centre = CGPoint(x: size.width / 2, y: edgeY)

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
                        width: Tuning.rangeRadius.width * Tuning.scale * grow,
                        height: Tuning.rangeRadius.height * Tuning.scale * grow
                    ),
                    gradient: Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.5), location: 0.35),
                        .init(color: .clear, location: 1)
                    ])
                )
            }

            // Additive: two lobes overlapping should read as more light, not
            // as the nearer one covering the further.
            context.blendMode = .plusLighter

            for (index, lobe) in Self.lobes.enumerated() {
                let colour = Self.palette[index].opacity(layer.alpha)
                let rise = levels[lobe.band]

                ellipse(
                    in: &context,
                    centre: CGPoint(
                        x: centre.x + lobe.x * Tuning.lobeSpacing * Tuning.scale,
                        y: centre.y + layer.dropBelowEdge * Tuning.scale
                    ),
                    radius: CGSize(
                        width: lobe.width * layer.widthScale * Tuning.glowWidth * Tuning.scale,
                        height: lobe.height * layer.heightScale * Tuning.glowHeight * Tuning.scale
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
/// Shared, because the halo and the surface are two views of one glow and
/// must rise together. They tick off the same display link, so the second
/// caller in a frame is handed what the first computed rather than advancing
/// the envelope twice.
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
        // The halo and the surface tick off the same display link, so the
        // second one through in a frame is handed what the first computed
        // rather than advancing the envelope a second time.
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
    /// Wraps the pill in its glow, reserving the room the halo blooms into.
    ///
    /// The padding is unconditional — it is in the layout whether or not a
    /// dictation is live. Reserving it only while glowing would resize the
    /// window mid-dictation, and re-centring the panel per frame is the same
    /// jitter the fixed preview width exists to avoid.
    func voiceGlow(shape: AnyShape, isActive: Bool) -> some View {
        self
            .padding(.horizontal, VoiceGlow.Tuning.horizontalBleed)
            .padding(.bottom, VoiceGlow.Tuning.reservedHeight)
            .background { VoiceGlow(role: .halo, shape: shape, isActive: isActive) }
            .overlay { VoiceGlow(role: .surface, shape: shape, isActive: isActive) }
    }
}
