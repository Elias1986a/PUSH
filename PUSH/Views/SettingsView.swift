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
        if selectedModel.isMoonshine {
            return MoonshineEngine.isModelDownloaded(selectedModel)
        }
        return WhisperEngine.isModelDownloaded(selectedModel)
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
                } else if selectedModel == .moonshineBase {
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
                            Button("Download (~134 MB)") {
                                downloadMoonshineBase()
                            }
                        }
                    }

                    if let downloadError {
                        Text(downloadError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Text("Moonshine Base model will be downloaded on first use.")
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
                                downloadSelectedModel()
                            }
                        }
                    }

                    if let downloadError {
                        Text(downloadError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    let modelPath = WhisperEngine.modelFolderURL(for: selectedModel)
                    HStack {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([modelPath])
                        }
                        .disabled(!isDownloaded)
                    }
                    Text(modelPath.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    Text("Models are downloaded automatically when needed and stored locally.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func downloadSelectedModel() {
        let model = appState.selectedWhisperModel
        isDownloading = true
        downloadError = nil
        Task {
            do {
                try await WhisperEngine.shared.loadModel(model)
                // Run warmup to compile Metal shaders so first transcription is fast
                await WhisperEngine.shared.warmup()
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

    private func downloadMoonshineBase() {
        isDownloading = true
        downloadError = nil
        Task {
            do {
                try await MoonshineEngine.shared.downloadBaseModel()
                // Load and warm up so first transcription is fast
                try await MoonshineEngine.shared.loadModel(.moonshineBase)
                await MoonshineEngine.shared.warmup()
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

            Text("Version 3.1.1")
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
