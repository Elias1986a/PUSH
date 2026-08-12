import SwiftUI

struct FloatingPillView: View {
    @EnvironmentObject var appState: AppState
    @State private var dotPhase1: CGFloat = 0
    @State private var dotPhase2: CGFloat = 0
    @State private var dotPhase3: CGFloat = 0

    /// Widest the pill grows once live text arrives. Past this the text scrolls
    /// instead, so the pill never creeps across the screen on a long dictation.
    private static let maxPreviewWidth: CGFloat = 360

    var body: some View {
        HStack(spacing: 6) {
            // Microphone icon
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(appState.isListening ? .red : .orange)

            if showPreview {
                livePreviewText
            } else {
                // Status text with animated dots
                HStack(alignment: .bottom, spacing: 0) {
                    Text(baseStatusText)
                        .font(.system(size: 11, weight: .medium))

                    if appState.isListening {
                        bouncingDots
                            .padding(.bottom, 1)  // Align with text baseline
                    }
                }
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
    }

    /// The rough in-flight transcript. Laid out at its natural width, then
    /// clamped to `maxPreviewWidth` with trailing alignment, so the newest words
    /// stay pinned to the right and older ones slide off the left edge under a
    /// short fade.
    private var livePreviewText: some View {
        Text(appState.livePartialText)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: Self.maxPreviewWidth, alignment: .trailing)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            // Dim once the hotkey is released: what's on screen is the captured
            // text, and cleanup is still to come.
            .opacity(appState.isListening ? 1 : 0.55)
            .animation(.easeOut(duration: 0.15), value: appState.livePartialText)
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

    /// Live text replaces the status label only while there is something to show
    /// and a dictation is actually in flight. Until the first partial lands
    /// (~2s in) this is false, so short utterances look exactly as they do today.
    private var showPreview: Bool {
        appState.showLivePreview
            && !appState.livePartialText.isEmpty
            && (appState.isListening || appState.isProcessing)
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
