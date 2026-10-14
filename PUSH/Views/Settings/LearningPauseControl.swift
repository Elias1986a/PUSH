import SwiftUI

/// Pause learning: the same shape as `TypingPauseControl`. Shown only while
/// "Learn from my writing and voice" is on, in the menu bar and in
/// Settings → Personal. Pausing stops anything new being kept, and the field
/// being written is dropped; what is already kept stays, and still helps.
struct LearningPauseControl: View {
    @State private var history = TypingHistoryStore.shared
    @State private var choosing = false

    var body: some View {
        if history.isOn {
            if let until = history.pausedUntil {
                HStack(spacing: 8) {
                    Label("Not learning until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Resume") { history.pausedUntil = nil }
                }
            } else if choosing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pause learning for how long?").foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button { choosing = false } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Cancel")
                    }
                    HStack(spacing: 6) {
                        Button("1 Hour") { pause(until: Date().addingTimeInterval(3600)) }
                        Button("Until Tomorrow") {
                            pause(until: Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)))
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text("Learning").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { choosing = true } label: { Label("Pause", systemImage: "pause.fill") }
                        .help("Stop keeping what you write for a while")
                }
            }
        }
    }

    private func pause(until date: Date) {
        history.pausedUntil = date
        choosing = false
    }
}
