import SwiftUI

/// Pause suggestions: a Pause button that then asks for how long, or the
/// pause in force with Resume. Shared by the menu bar and Settings → Typing.
struct TypingPauseControl: View {
    @Environment(AppState.self) private var appState
    @State private var choosing = false

    var body: some View {
        if let until = appState.typingPausedUntil, until > Date() {
            HStack(spacing: 8) {
                Label("Paused until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Resume") { appState.typingPausedUntil = nil }
            }
        } else if choosing {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pause suggestions for how long?").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { choosing = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Cancel")
                        .accessibilityLabel("Cancel")
                }
                HStack(spacing: 6) {
                    Button("1 Hour") { pause(until: Date().addingTimeInterval(3600)) }
                    Button("Until Tomorrow") {
                        pause(until: Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)))
                    }
                    if let app = TypingCoordinator.shared.lastApp,
                       !appState.typingExcludedApps.contains(app.bundleID) {
                        Button("Always in \(app.name)") {
                            appState.typingExcludedApps.append(app.bundleID)
                            choosing = false
                        }
                        .help("Turns suggestions off in \(app.name) until you remove it in Settings ▸ TYPE")
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Text("Suggestions").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { choosing = true } label: { Label("Pause", systemImage: "pause.fill") }
            }
        }
    }

    private func pause(until date: Date) {
        appState.typingPausedUntil = date
        choosing = false
    }
}
