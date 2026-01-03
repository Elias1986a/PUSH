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

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
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
                HStack {
                    Text("Push-to-talk:")
                    Spacer()
                    Text("⌥ Right Option (hold)")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }

                Toggle("Enable hotkey", isOn: $appState.hotkeyEnabled)
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

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("PUSH")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .foregroundColor(.secondary)

            Text("Voice to text with offline AI")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("Hold Right Option to speak")
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
