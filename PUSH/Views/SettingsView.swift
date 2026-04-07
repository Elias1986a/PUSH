import SwiftUI
import LaunchAtLogin
import AppKit

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

            AboutView()
                .environmentObject(appState)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 400)
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
    @State private var isDownloading = false
    @State private var downloadError: String?

    private var selectedModel: AppState.WhisperModel {
        appState.selectedWhisperModel
    }

    private var isDownloaded: Bool {
        if selectedModel == .moonshineTiny {
            return true // Bundled with the framework
        }
        switch selectedModel.engineType {
        case .moonshine:
            return MoonshineEngine.isModelDownloaded(selectedModel)
        case .parakeet:
            return ParakeetEngine.isModelDownloaded()
        case .qwen3:
            return Qwen3Engine.isModelDownloaded()
        case .whisperKit:
            return WhisperEngine.isModelDownloaded(selectedModel)
        }
    }

    var body: some View {
        Form {
            Section("Speech Model") {
                Picker("Model", selection: $appState.selectedWhisperModel) {
                    ForEach(AppState.WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                Text(selectedModel.modelDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if selectedModel == .moonshineTiny {
                    HStack(spacing: 8) {
                        Label("Bundled", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                    }
                    Text("Moonshine Tiny is included with the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 8) {
                        if isDownloaded {
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Not downloaded", systemImage: "icloud.and.arrow.down")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        } else if !isDownloaded {
                            Button("Download") {
                                downloadModel()
                            }
                        }
                    }

                    if let downloadError {
                        Text(downloadError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Text("Models are downloaded automatically when needed and stored locally.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func downloadModel() {
        let model = appState.selectedWhisperModel
        isDownloading = true
        downloadError = nil
        Task {
            do {
                switch model.engineType {
                case .moonshine:
                    try await MoonshineEngine.shared.downloadBaseModel()
                    try await MoonshineEngine.shared.loadModel(model)
                    await MoonshineEngine.shared.warmup()
                case .parakeet:
                    try await ParakeetEngine.shared.loadModel()
                    await ParakeetEngine.shared.warmup()
                case .qwen3:
                    try await Qwen3Engine.shared.loadModel()
                    await Qwen3Engine.shared.warmup()
                case .whisperKit:
                    try await WhisperEngine.shared.loadModel(model)
                    await WhisperEngine.shared.warmup()
                }
                await MainActor.run {
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    downloadError = error.localizedDescription
                    isDownloading = false
                }
            }
        }
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

            Text("Version 4.0.0")
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
