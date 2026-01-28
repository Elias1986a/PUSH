import SwiftUI
import LaunchAtLogin

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ModelsSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }

            AutocompleteSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Autocomplete", systemImage: "text.cursor")
                }

            AboutView()
                .environmentObject(appState)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 480)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle("Start PUSH at login")
            }

            Section("Hotkey") {
                Picker("Push-to-talk key", selection: $appState.selectedHotkey) {
                    ForEach(AppState.Hotkey.allCases) { hotkey in
                        Text(hotkey.displayName).tag(hotkey)
                    }
                }

                Toggle("Enable hotkey", isOn: $appState.hotkeyEnabled)
                Toggle("Play sound when recording starts", isOn: $appState.playSoundOnStart)
            }

            Section("Wake Word (Hands-Free Mode)") {
                Toggle("Enable wake word activation", isOn: $appState.wakeWordEnabled)
                    .onChange(of: appState.wakeWordEnabled) { _, newValue in
                        if newValue {
                            WakeWordListener.shared.startListening()
                        } else {
                            WakeWordListener.shared.stopListening()
                        }
                    }

                if appState.wakeWordEnabled {
                    HStack {
                        Text("Wake word")
                        Spacer()
                        TextField("push", text: $appState.wakeWord)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    Text("Say \"\(appState.wakeWord)\" to start recording. Recording stops automatically after 1 second of silence. Push-to-talk hotkey still works.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Models Settings

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var modelManager = ModelManager.shared

    var body: some View {
        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $appState.selectedWhisperModel) {
                    ForEach(AppState.WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                ModelStatusRow(
                    model: appState.selectedWhisperModel.rawValue,
                    isDownloaded: modelManager.isModelDownloaded(appState.selectedWhisperModel.rawValue),
                    downloadProgress: modelManager.downloadProgress[appState.selectedWhisperModel.rawValue],
                    onDownload: {
                        Task {
                            await modelManager.downloadWhisperModel(appState.selectedWhisperModel)
                        }
                    }
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ModelStatusRow: View {
    let model: String
    let isDownloaded: Bool
    let downloadProgress: Double?
    let onDownload: () -> Void

    var body: some View {
        HStack {
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Downloaded")
                    .foregroundColor(.secondary)
            } else if let progress = downloadProgress {
                ProgressView(value: progress)
                    .frame(width: 100)
                Text("\(Int(progress * 100))%")
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            } else {
                Button("Download") {
                    onDownload()
                }
            }
        }
    }
}

// MARK: - Autocomplete Settings

struct AutocompleteSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var modelManager = ModelManager.shared
    @State private var enableError: String?
    @State private var isToggling = false

    private var isModelReady: Bool {
        modelManager.isTextModelDownloaded(.tinyLlama)
    }

    var body: some View {
        Form {
            Section("Predictive Text") {
                Toggle("Enable autocomplete", isOn: Binding(
                    get: { appState.autocompleteEnabled },
                    set: { newValue in
                        guard !isToggling else { return }
                        isToggling = true
                        enableError = nil
                        if newValue {
                            guard isModelReady else {
                                enableError = "Download the text model first."
                                isToggling = false
                                return
                            }
                            Task {
                                do {
                                    try await AutocompleteManager.shared.enable()
                                    appState.autocompleteEnabled = true
                                } catch {
                                    print("Failed to enable autocomplete: \(error)")
                                    enableError = error.localizedDescription
                                }
                                isToggling = false
                            }
                        } else {
                            AutocompleteManager.shared.disable()
                            appState.autocompleteEnabled = false
                            isToggling = false
                        }
                    }
                ))
                .disabled(!isModelReady)

                if !isModelReady {
                    Text("Download the text prediction model below to enable autocomplete.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if let error = enableError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if appState.autocompleteEnabled {
                    Text("Tab to accept next word, ` (backtick) to accept full suggestion, Esc to dismiss.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Text Prediction Model") {
                let model = TextPredictionEngine.TextModel.tinyLlama
                HStack {
                    VStack(alignment: .leading) {
                        Text(model.displayName)
                            .font(.system(size: 13))
                    }
                    Spacer()
                    ModelStatusRow(
                        model: model.rawValue,
                        isDownloaded: modelManager.isTextModelDownloaded(model),
                        downloadProgress: modelManager.downloadProgress[model.rawValue],
                        onDownload: {
                            Task {
                                await modelManager.downloadTextModel(model)
                            }
                        }
                    )
                }
            }

            Section("About You") {
                Text("Describe yourself and your writing style. This helps the AI predict text that sounds like you.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $appState.personalContext)
                    .font(.system(size: 12))
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.3), width: 1)
                    .onChange(of: appState.personalContext) { _, newValue in
                        AutocompleteManager.shared.updatePersonalContext(newValue)
                    }

                if appState.personalContext.isEmpty {
                    Text("Example: \"I'm a software developer. I write concise, technical emails. I prefer short sentences and avoid jargon when possible.\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About View

struct AboutView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("PUSH")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 2.1.3")
                .foregroundColor(.secondary)

            Text("Voice to text with offline AI")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("Hold \(appState.selectedHotkey.displayName) to speak")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
