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
        appState.isListening || appState.isProcessing
    }

    private var baseStatusText: String {
        if appState.isProcessing {
            return "Processing..."
        } else if appState.isListening {
            return "Listening"
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

#Preview {
    FloatingPillView()
        .environmentObject(AppState.shared)
        .padding(50)
        .background(Color.gray.opacity(0.3))
}
