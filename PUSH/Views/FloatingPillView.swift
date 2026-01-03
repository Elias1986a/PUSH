import SwiftUI

struct FloatingPillView: View {
    @EnvironmentObject var appState: AppState
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            // Animated indicator
            ZStack {
                if appState.isListening {
                    // Pulsing circles for listening
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .frame(width: 12, height: 12)
                            .scaleEffect(1 + animationPhase * CGFloat(index + 1) * 0.3)
                            .opacity(1 - animationPhase * 0.3)
                    }
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                } else if appState.isProcessing {
                    // Spinning indicator for processing
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                }
            }
            .frame(width: 20, height: 20)

            // Status text
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .opacity(shouldShow ? 1 : 0)
        .scaleEffect(shouldShow ? 1 : 0.8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: shouldShow)
        .onAppear {
            startAnimation()
        }
    }

    private var shouldShow: Bool {
        appState.isListening || appState.isProcessing
    }

    private var statusText: String {
        if appState.isProcessing {
            return "Processing..."
        } else if appState.isListening {
            return "Listening..."
        } else {
            return ""
        }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            animationPhase = 1
        }
    }
}

#Preview {
    FloatingPillView()
        .environmentObject({
            let state = AppState.shared
            Task { @MainActor in
                state.isListening = true
            }
            return state
        }())
        .padding(50)
        .background(Color.gray.opacity(0.3))
}
