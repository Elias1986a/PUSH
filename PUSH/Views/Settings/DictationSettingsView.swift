import SwiftUI
import AppKit
import AVFoundation
import PUSHCore

// MARK: - Dictation

struct DictationSettingsView: View {
    @EnvironmentObject var appState: AppState

    /// Snapshot of the attached input devices. Held in @State rather than
    /// enumerated from `body`: each refresh is a handful of synchronous
    /// CoreAudio round-trips, and a Form re-renders on every keystroke
    /// anywhere in the window.
    @State private var inputDevices: [AudioInputDevices.Device] = []
    @State private var systemDefaultName: String?

    var body: some View {
        Form {
            Section("Microphone") {
                Picker("Input device", selection: $appState.inputDeviceUID) {
                    Text(systemDefaultName.map { "System default (\($0))" } ?? "System default")
                        .tag(String?.none)
                    if !inputDevices.isEmpty {
                        Divider()
                        ForEach(inputDevices) { device in
                            Text(device.name).tag(String?.some(device.uid))
                        }
                    }
                }

                // A saved device that is not attached stays selected rather
                // than silently resetting: unplugging an interface for the
                // afternoon should not lose the setting. Recording falls back
                // to the system default until it is back.
                if let uid = appState.inputDeviceUID, !inputDevices.contains(where: { $0.uid == uid }) {
                    Label(
                        "That microphone is not connected right now. PUSH will use the system default until it is back.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Text("System default follows whatever macOS is using, which changes when you connect AirPods or a headset. Pick a device to keep PUSH on it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Push to talk") {
                Toggle("Hold a key to dictate", isOn: $appState.hotkeyEnabled)

                Picker("Key", selection: $appState.selectedHotkey) {
                    ForEach(AppState.Hotkey.allCases) { hotkey in
                        Text(hotkey.displayName).tag(hotkey)
                    }
                }
                .disabled(!appState.hotkeyEnabled)

                Text("Hold the key, speak, release. Press ⎋ Esc while recording to cancel without inserting text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("While recording") {
                Toggle("Play a sound when recording starts", isOn: $appState.playSoundOnStart)

                Picker("Other apps' audio", selection: $appState.mediaBehavior) {
                    ForEach(MediaBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)

                Text("Lowers the output volume while you dictate, then restores it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Wake word") {
                Toggle("Start recording when you say a word", isOn: $appState.wakeWordEnabled)
                    .onChange(of: appState.wakeWordEnabled) { _, newValue in
                        if newValue {
                            WakeWordListener.shared.startListening()
                        } else {
                            WakeWordListener.shared.stopListening()
                        }
                    }

                HStack {
                    Text("Word")
                    Spacer()
                    // labelsHidden + prompt: inside a Form the first argument
                    // becomes a *label* beside the field, so "push" was drawn
                    // twice — once as a label, once as placeholder text.
                    TextField("", text: $appState.wakeWord, prompt: Text("push"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 128)
                }
                .disabled(!appState.wakeWordEnabled)

                Text("Recording stops after a second of silence. Push to talk keeps working. Listening for a wake word holds the microphone open the whole time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshDevices)
        // CoreAudio posts this when a device is attached or removed, so the
        // list is right without the user reopening the pane.
        .onReceive(NotificationCenter.default.publisher(
            for: .AVAudioEngineConfigurationChange)) { _ in
            refreshDevices()
        }
    }

    private func refreshDevices() {
        inputDevices = AudioInputDevices.available()
        systemDefaultName = AudioInputDevices.systemDefault()?.name
    }
}
