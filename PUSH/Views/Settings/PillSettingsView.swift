import SwiftUI
import AppKit
import PUSHCore

// MARK: - Pill

/// The pill's section, shown in Settings ▸ Talk (the Pill pane was folded
/// into Talk, 2026-10-14: everything here is about dictation).
struct PillSettingsSections: View {
    @Environment(AppState.self) private var appState

    /// Keyed off the *selected* model rather than the active one, so the toggle
    /// greys out the moment you pick another model instead of waiting for the
    /// swap to finish loading.
    private var supportsLivePreview: Bool {
        appState.selectedWhisperModel.engineType == .parakeetStreaming
    }

    /// Live text needs Streaming: turning it on with another model asks to
    /// switch (and download, if needed) rather than greying the switch out.
    @State private var askingToSwitch = false
    @State private var switching = false
    @State private var switchProgress = 0.0
    @State private var switchError: String?

    private var streamingOnDisk: Bool { ModelAvailability.isDownloaded(.parakeetStreaming) }

    var body: some View {
        // `@Observable` has no projected value of its own; `@Bindable`
        // is what gives the controls below their `$appState` bindings.
        @Bindable var appState = appState

        Section {
            HStack(spacing: 16) {
                Spacer()
                ForEach(AppState.PillPosition.allCases) { position in
                    PillPositionThumbnail(
                        position: position,
                        isSelected: appState.pillPosition == position
                    )
                    .onTapGesture { appState.pillPosition = position }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(position.displayName)
                    .accessibilityAddTraits(appState.pillPosition == position ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { appState.pillPosition = position }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            Text("At the bottom the pill floats as a capsule, out of the way. At the top it hangs off the screen edge under the notch, where you are already reading.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show text in the pill as you speak", isOn: Binding(
                get: { appState.showLivePreview && supportsLivePreview },
                set: { on in
                    if on && !supportsLivePreview { askingToSwitch = true } else { appState.showLivePreview = on }
                }))
                .disabled(switching)
                .confirmationDialog("Switch to Parakeet Streaming?", isPresented: $askingToSwitch) {
                    Button(streamingOnDisk ? "Switch" : "Download and Switch") { switchToStreaming() }
                } message: {
                    Text("Live text needs the Parakeet Streaming model, which is English only. "
                         + (streamingOnDisk ? "It's already on this Mac." : "It's a 660 MB download.")
                         + " You can switch back in Models.")
                }

            if switching {
                ProgressView(value: switchProgress, total: 1).progressViewStyle(.linear)
                Text(streamingOnDisk ? "Switching to Parakeet Streaming…" : "Downloading Parakeet Streaming… \(Int(switchProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let switchError {
                Text(switchError).font(.caption).foregroundStyle(.red)
            }

            Picker("Text size", selection: $appState.previewSize) {
                ForEach(AppState.PreviewSize.allCases) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!supportsLivePreview || !appState.showLivePreview)
        } header: {
            Text("Pill")
        } footer: {
            Text(supportsLivePreview
                 ? "The text in the pill is a rough transcript, about two seconds behind you; the final text is cleaned up before it is inserted."
                 : "Live text needs the Parakeet Streaming model. Turning it on switches to Streaming, after a download if it isn't on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What Settings ▸ Models does for a row: select it, then download (if
    /// needed), load and warm it.
    private func switchToStreaming() {
        switching = true
        switchProgress = 0
        switchError = nil
        appState.selectedWhisperModel = .parakeetStreaming
        appState.showLivePreview = true
        Task {
            do {
                try await ModelDownload.run(.parakeetStreaming) { switchProgress = $0 }
            } catch is CancellationError {
                // Superseded by another activation; nothing to report.
            } catch {
                switchError = error.localizedDescription
            }
            switching = false
        }
    }
}
