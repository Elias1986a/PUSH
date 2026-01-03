import SwiftUI

struct FloatingPillView: View {
    @EnvironmentObject var appState: AppState
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        pillContent
            .opacity(shouldShow ? 1 : 0)
            .scaleEffect(shouldShow ? 1 : 0.8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: shouldShow)
            .onAppear {
                startAnimation()
            }
    }

    private var pillContent: some View {
        HStack(spacing: 8) {
            indicatorView
                .frame(width: 20, height: 20)

            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(pillBackground)
    }

    @ViewBuilder
    private var indicatorView: some View {
        if appState.isListening {
            listeningIndicator
        } else if appState.isProcessing {
            processingIndicator
        } else {
            Color.clear
        }
    }

    private var listeningIndicator: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .scaleEffect(1 + animationPhase * 0.2)
    }

    private var processingIndicator: some View {
        ProgressView()
            .scaleEffect(0.6)
            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
    }

    private var pillBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
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
        .environmentObject(AppState.shared)
        .padding(50)
        .background(Color.gray.opacity(0.3))
}
