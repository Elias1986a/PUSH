import SwiftUI
import AppKit

struct FloatingPillView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var revealer = PreviewRevealer()
    @State private var dotPhase1: CGFloat = 0
    @State private var dotPhase2: CGFloat = 0
    @State private var dotPhase3: CGFloat = 0

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

    var body: some View {
        HStack(spacing: 6) {
            // Microphone icon
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(appState.isListening ? .red : .orange)

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
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        )
        .opacity(shouldShow ? 1 : 0)
        .scaleEffect(shouldShow ? 1 : 0.85)
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
                .fill(.primary)
                .frame(width: 3, height: 3)
                .offset(y: dotPhase1 * -2)

            Circle()
                .fill(.primary)
                .frame(width: 3, height: 3)
                .offset(y: dotPhase2 * -2)

            Circle()
                .fill(.primary)
                .frame(width: 3, height: 3)
                .offset(y: dotPhase3 * -2)
        }
        .padding(.leading, 1)
    }

    private var shouldShow: Bool {
        appState.isListening || appState.isProcessing || !appState.isModelReady || appState.isWarmingUp
    }

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
            // Recording can start before the model is ready, so "Listening"
            // takes precedence — the mic really is capturing.
            return "Listening"
        } else if appState.isProcessing {
            return "Processing..."
        } else if !appState.isModelReady {
            return "Loading model..."
        } else if appState.isWarmingUp {
            // Model is usable; shaders are still warming in the background.
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
#Preview {
    FloatingPillView()
        .environmentObject(AppState.shared)
        .padding(50)
        .background(Color.gray.opacity(0.3))
}
#endif
