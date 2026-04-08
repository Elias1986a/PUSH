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
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus: String = ""
    @State private var downloadError: String?

    private var selectedModel: AppState.WhisperModel {
        appState.selectedWhisperModel
    }

    private var modelFolderPath: URL {
        switch selectedModel.engineType {
        case .moonshine:
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("PUSH/moonshine-models/base-en", isDirectory: true)
        case .parakeet:
            return ParakeetEngine.modelDirectory
        case .whisperKit:
            return WhisperEngine.modelFolderURL(for: selectedModel)
        }
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
                            // No button while downloading
                        } else if isDownloaded {
                            Button("Delete") {
                                deleteModel()
                            }
                            .foregroundColor(.red)
                        } else {
                            Button("Download") {
                                downloadModel()
                            }
                        }
                    }

                    if isDownloading {
                        VStack(alignment: .leading, spacing: 4) {
                            if downloadProgress > 0 {
                                ProgressView(value: downloadProgress, total: 1.0)
                                    .progressViewStyle(.linear)
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                            }
                            Text(downloadStatus.isEmpty ? "Downloading..." : downloadStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let downloadError {
                        Text(downloadError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if !isDownloading && isDownloaded {
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: modelFolderPath.path)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }

                    if !isDownloading && !isDownloaded {
                        Text("Models are downloaded automatically when needed and stored locally.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func downloadModel() {
        let model = appState.selectedWhisperModel
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Preparing download..."
        downloadError = nil
        Task {
            do {
                switch model.engineType {
                case .moonshine:
                    await MainActor.run { downloadStatus = "Downloading Moonshine model..." }
                    try await MoonshineEngine.shared.downloadBaseModel()
                    await MainActor.run {
                        downloadProgress = 0.8
                        downloadStatus = "Loading model..."
                    }
                    try await MoonshineEngine.shared.loadModel(model)
                    await MainActor.run {
                        downloadProgress = 0.9
                        downloadStatus = "Warming up..."
                    }
                    await MoonshineEngine.shared.warmup()
                case .parakeet:
                    await MainActor.run { downloadStatus = "Downloading Parakeet model (~400 MB)..." }
                    // Poll download directory for progress
                    let pollTask = Task {
                        let expectedSize: Double = 400_000_000 // ~400 MB
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(1))
                            let dir = ParakeetEngine.modelDirectory
                            let size = Self.directorySize(at: dir)
                            let progress = min(size / expectedSize, 0.95)
                            await MainActor.run {
                                downloadProgress = progress
                                if progress > 0.01 {
                                    downloadStatus = "Downloading... \(Int(progress * 100))%"
                                }
                            }
                        }
                    }
                    try await ParakeetEngine.shared.loadModel()
                    pollTask.cancel()
                    await MainActor.run {
                        downloadProgress = 0.9
                        downloadStatus = "Warming up..."
                    }
                    await ParakeetEngine.shared.warmup()
                case .whisperKit:
                    await MainActor.run { downloadStatus = "Downloading model..." }
                    // Poll download directory for progress
                    let whisperPollTask = Task {
                        let expectedSize: Double = Double(model == .whisperLargeV3Turbo ? 632_000_000 : 600_000_000)
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(1))
                            let dir = WhisperEngine.modelFolderURL(for: model)
                            let size = Self.directorySize(at: dir)
                            let progress = min(size / expectedSize, 0.95)
                            await MainActor.run {
                                downloadProgress = progress
                                if progress > 0.01 {
                                    downloadStatus = "Downloading... \(Int(progress * 100))%"
                                }
                            }
                        }
                    }
                    try await WhisperEngine.shared.loadModel(model)
                    whisperPollTask.cancel()
                    await MainActor.run {
                        downloadProgress = 0.9
                        downloadStatus = "Warming up..."
                    }
                    await WhisperEngine.shared.warmup()
                }
                await MainActor.run {
                    downloadProgress = 1.0
                    downloadStatus = "Complete!"
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

    private static func directorySize(at url: URL) -> Double {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Double = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Double(size)
            }
        }
        return total
    }

    private func deleteModel() {
        let model = appState.selectedWhisperModel
        downloadError = nil

        let urlToDelete: URL
        switch model.engineType {
        case .moonshine:
            urlToDelete = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("PUSH/moonshine-models/base-en", isDirectory: true)
        case .parakeet:
            urlToDelete = ParakeetEngine.modelDirectory
        case .whisperKit:
            urlToDelete = WhisperEngine.modelFolderURL(for: model)
        }

        guard FileManager.default.fileExists(atPath: urlToDelete.path) else { return }

        do {
            try FileManager.default.removeItem(at: urlToDelete)
        } catch {
            downloadError = "Failed to delete: \(error.localizedDescription)"
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
