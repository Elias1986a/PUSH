import SwiftUI
import UniformTypeIdentifiers

/// The prompter's settings: the script, how it looks, and how it moves.
struct TeleprompterSettingsView: View {
    @ObservedObject private var settings = TeleprompterState.shared
    @ObservedObject private var session = TeleprompterSession.shared

    @State private var loadError: String?

    private var wordCount: Int {
        settings.script.split { $0.isWhitespace }.count
    }

    var body: some View {
        Form {
            Section("Script") {
                TextEditor(text: $settings.script)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button("Load from File…") { loadFromFile() }
                    Button("Paste") { pasteFromClipboard() }
                    Spacer()
                    Text("\(wordCount) words · about \(estimatedMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Appearance") {
                Picker("Size", selection: $settings.size) {
                    ForEach(TeleprompterState.Size.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Text("Always three lines. A bigger size means bigger type, not more text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Hide from screen recordings", isOn: $settings.hideFromScreenRecording)
                    .onChange(of: settings.hideFromScreenRecording) { _, _ in
                        TeleprompterWindow.shared.applySharingType()
                    }
                Text("The prompter stays on your screen but is excluded from screen capture, so it never appears in the recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scrolling") {
                Toggle("Follow my voice", isOn: $settings.followVoice)
                Text("PUSH listens as you read and moves the script to keep up. It holds still if you go off-script, and falls back to the speed below if it loses you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if TeleprompterSession.readiness == .needsDownload {
                    Label(
                        "Voice-following needs the Parakeet model. Download it in Models.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $settings.wordsPerMinute, in: 60...400, step: 10)
                        Text("\(Int(settings.wordsPerMinute)) wpm")
                            .font(.caption.monospacedDigit())
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                Text(settings.followVoice
                     ? "Used only when voice-following loses the thread."
                     : "The pace the script scrolls at.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("While the prompter is running") {
                shortcut("↑ / ↓", "Move back or forward one line")
                shortcut("← / →", "Slower or faster, by 10 wpm")
                Text("The arrow keys only belong to the prompter while it is running, so they work normally the rest of the time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Rough read time at the configured pace, so the length of a script means
    /// something before you record it.
    private var estimatedMinutes: Int {
        max(1, Int((Double(wordCount) / max(settings.wordsPerMinute, 1)).rounded()))
    }

    private func shortcut(_ keys: String, _ meaning: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(meaning)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Loading

    private func loadFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text, .rtf, UTType("net.daringfireball.markdown") ?? .plainText]
        panel.message = "Choose a script"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            settings.script = try String(contentsOf: url, encoding: .utf8)
            loadError = nil
        } catch {
            // Not every text file is UTF-8; say so rather than silently
            // loading nothing.
            loadError = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            loadError = "There's no text on the clipboard."
            return
        }
        settings.script = text
        loadError = nil
    }
}
