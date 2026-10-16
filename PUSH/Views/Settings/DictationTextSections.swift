import SwiftUI
import AppKit
import PUSHCore

// MARK: - How dictated text is written

/// One "Text" section: double spacing, spoken corrections and California
/// mode, what happens to dictated words before they are pasted. They were a Text pane of their
/// own; with Type beside dictation that name read as covering typing too,
/// so they live in the Dictation pane (user, 2026-10-12).
struct DictationTextSections: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // `@Observable` has no projected value of its own; `@Bindable`
        // is what gives the controls below their `$appState` bindings.
        @Bindable var appState = appState

        Section {
            Toggle("Double space after sentences", isOn: $appState.doubleSpaceAfterSentence)

            Toggle(isOn: $appState.resolveSelfCorrections) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Act on corrections you say out loud")
                    Text("Say “the red car, I mean the blue car” and only “the blue car” is pasted. Also recognizes “no wait”, “make that”, and “scratch that”. “Sorry” counts only when set off by commas, and “actually” is ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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

                Text("PUSHTYPE inserts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Book the table for eight")
            }
            .padding(.vertical, 4)

            Toggle(isOn: $appState.californiaMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("California mode: remove casual “like”")
                    Text("“It was like really good” becomes “It was really good.” Keeps “I like it”, “looks like rain”, “like I said”, “like 30 minutes”, and “he was like, no way.”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Text")
        }
    }
}
