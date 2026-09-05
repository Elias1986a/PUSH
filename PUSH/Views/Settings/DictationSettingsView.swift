import SwiftUI
import AppKit
import PUSHCore

// MARK: - Dictation

struct DictationSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
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
    }
}
