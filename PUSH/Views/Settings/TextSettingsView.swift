import SwiftUI
import AppKit
import PUSHCore

// MARK: - Text

struct TextSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Formatting") {
                Toggle("Double space after sentences", isOn: $appState.doubleSpaceAfterSentence)
            }

            Section("Spoken corrections") {
                Toggle("Act on corrections you say out loud", isOn: $appState.resolveSelfCorrections)

                Text("Say “the red car, I mean the blue car” and only “the blue car” is pasted. Also recognises “no wait”, “make that” and “scratch that”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Showing it beats describing it: the old copy spent a
                // paragraph on what one example makes obvious.
                VStack(alignment: .leading, spacing: 8) {
                    Text("You say")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Book the table for ")
                        + Text("six").strikethrough().foregroundColor(.secondary)
                        + Text(", I mean eight")

                    Divider()

                    Text("PUSH inserts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Book the table for eight")
                }
                .padding(.vertical, 4)

                Text("Words like “sorry” and “actually” are ignored on purpose — too often ordinary speech, and a wrong guess deletes words you meant to keep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
