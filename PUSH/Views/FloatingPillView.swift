import SwiftUI

struct FloatingPillView: View {
    @EnvironmentObject var appState: AppState
    @State private var dotPhase1: CGFloat = 0
    @State private var dotPhase2: CGFloat = 0
    @State private var dotPhase3: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            // Microphone icon
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(appState.isListening ? .red : .orange)

            if liveText.isEmpty {
                // Status text with animated dots
                HStack(alignment: .bottom, spacing: 0) {
                    Text(baseStatusText)
                        .font(.system(size: 11, weight: .medium))

                    if appState.isListening {
                        bouncingDots
                            .padding(.bottom, 1)  // Align with text baseline
                    }
                }
            } else {
                // Italic and dimmed on purpose: this is raw engine output, not
                // the post-processed text that will actually be pasted.
                Text(liveText)
                    .font(.system(size: 11, weight: .medium))
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .animation(.easeOut(duration: 0.15), value: liveText)
        .fixedSize()
        // The panel is a fixed width so it never has to resize mid-sentence;
        // this keeps the capsule centred in it as the text grows and shrinks.
        .frame(maxWidth: .infinity)
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

    /// The provisional transcript, shown only while it can actually be current —
    /// a stale tail must never sit under "Loading model..." between takes.
    private var liveText: String {
        guard appState.showLiveTranscript,
              appState.isListening || appState.isProcessing,
              !appState.modelUnavailable,
              !appState.liveTranscript.isEmpty
        else { return "" }
        return LiveTranscript.tail(of: appState.liveTranscript)
    }

    private var shouldShow: Bool {
        appState.isListening || appState.isProcessing || !appState.isModelReady || appState.isWarmingUp
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
#Preview("Status") {
    FloatingPillView()
        .environmentObject(AppState.shared)
        .frame(width: 520)
        .padding(50)
        .background(Color.gray.opacity(0.3))
}

#Preview("Live text") {
    FloatingPillView()
        .environmentObject(AppState.shared)
        .frame(width: 520)
        .padding(50)
        .background(Color.gray.opacity(0.3))
        .onAppear {
            AppState.shared.isListening = true
            AppState.shared.liveTranscript =
                "the pill shows what you are saying while you are still saying it"
        }
}
#endif
