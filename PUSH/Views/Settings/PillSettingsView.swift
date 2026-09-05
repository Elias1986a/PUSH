import SwiftUI
import AppKit
import PUSHCore

// MARK: - Pill

struct PillSettingsView: View {
    @Environment(AppState.self) private var appState

    /// Keyed off the *selected* model rather than the active one, so the toggle
    /// greys out the moment you pick another model instead of waiting for the
    /// swap to finish loading.
    private var supportsLivePreview: Bool {
        appState.selectedWhisperModel.engineType == .parakeetStreaming
    }

    var body: some View {
        // `@Observable` has no projected value of its own; `@Bindable`
        // is what gives the controls below their `$appState` bindings.
        @Bindable var appState = appState

        Form {
            Section("Position") {
                HStack(spacing: 26) {
                    Spacer()
                    ForEach(AppState.PillPosition.allCases) { position in
                        PillPositionThumbnail(
                            position: position,
                            isSelected: appState.pillPosition == position
                        )
                        .onTapGesture { appState.pillPosition = position }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)

                Text("At the bottom the pill floats as a capsule, out of the way. At the top it hangs off the screen edge under the notch, where you are already reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Live preview") {
                Toggle("Show text in the pill as you speak", isOn: $appState.showLivePreview)
                    .disabled(!supportsLivePreview)

                Picker("Text size", selection: $appState.previewSize) {
                    ForEach(AppState.PreviewSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!supportsLivePreview || !appState.showLivePreview)

                Text(supportsLivePreview
                     ? "A rough transcript, about two seconds behind you — the final text is cleaned up before it is inserted."
                     : "Only Parakeet Streaming transcribes while you speak, and \(appState.selectedWhisperModel.shortName) is selected. Switch in Models to turn this on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
