import SwiftUI
import AppKit
import AVFoundation
import PUSHCore

// MARK: - Dictation

struct DictationSettingsView: View {
    @Environment(AppState.self) private var appState

    /// Snapshot of the attached input devices. Held in @State rather than
    /// enumerated from `body`: each refresh is a handful of synchronous
    /// CoreAudio round-trips, and a Form re-renders on every keystroke
    /// anywhere in the window.
    @State private var inputDevices: [AudioInputDevices.Device] = []
    /// The microphone recording would use right now.
    @State private var inUse: String?

    var body: some View {
        // `@Observable` has no projected value of its own; `@Bindable`
        // is what gives the controls below their `$appState` bindings.
        @Bindable var appState = appState

        Form {
            Section("Microphone") {
                ForEach(Array(appState.inputDevicePriority.enumerated()), id: \.element.id) { index, device in
                    microphoneRow(device, at: index)
                }

                HStack {
                    Menu("Add microphone") {
                        ForEach(addableDevices) { device in
                            Button(device.name) {
                                appState.inputDevicePriority.append(.init(uid: device.uid, name: device.name))
                            }
                        }
                    }
                    .disabled(addableDevices.isEmpty)
                    .fixedSize()
                    Spacer()
                    if let inUse {
                        Text("Recording from \(inUse)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(appState.inputDevicePriority.isEmpty
                     ? "PUSH uses the system default, which changes when you connect AirPods or a headset. Add microphones to choose which one PUSH uses."
                     : "PUSH uses the first microphone on the list that is connected, otherwise the system default. With the lid closed, the built-in microphone is skipped.")
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

                // Choosing one plays it, so the menu doubles as a preview.
                Picker("Sound", selection: $appState.chirpSound) {
                    ForEach(ChirpSound.allCases) { sound in
                        Text(sound.displayName).tag(sound)
                    }
                }
                .disabled(!appState.playSoundOnStart)

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
        .onChange(of: appState.inputDevicePriority) { _, _ in refreshDevices() }
        .onReceive(NotificationCenter.default.publisher(
            for: .AVAudioEngineConfigurationChange)) { _ in
            refreshDevices()
        }
    }

    /// One ranked microphone: its name, whether it is plugged in, and
    /// controls to move it up or take it off the list.
    private func microphoneRow(_ device: AppState.InputDevicePreference, at index: Int) -> some View {
        HStack {
            Text("\(index + 1).")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(device.name)
            if !inputDevices.contains(where: { $0.uid == device.uid }) {
                Text("Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.inputDevicePriority.swapAt(index, index - 1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Prefer this microphone")
            Button {
                appState.inputDevicePriority.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove from the list")
        }
    }

    /// Connected microphones not on the list yet.
    private var addableDevices: [AudioInputDevices.Device] {
        inputDevices.filter { device in !appState.inputDevicePriority.contains { $0.uid == device.uid } }
    }

    private func refreshDevices() {
        inputDevices = AudioInputDevices.available()
        let priority = appState.inputDevicePriority.map(\.uid)
        inUse = (AudioInputDevices.preferred(from: priority) ?? AudioInputDevices.systemDefault())?.name
    }
}
