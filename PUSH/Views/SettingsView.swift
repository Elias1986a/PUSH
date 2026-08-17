import SwiftUI
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

            DictionarySettingsView()
                .tabItem {
                    Label("Dictionary", systemImage: "text.book.closed")
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
    @StateObject private var launchAtLogin = LaunchAtLoginModel()

    /// Keyed off the *selected* model rather than the active one, so the toggle
    /// greys out the moment you pick another model instead of waiting for the
    /// swap to finish loading.
    private var supportsLivePreview: Bool {
        appState.selectedWhisperModel.engineType == .parakeetStreaming
    }

    var body: some View {
        Form {
            Section {
                // Not LaunchAtLogin.Toggle: its binding reads
                // SMAppService.status synchronously from the view body, which
                // blocks the main thread ~61ms per render pass. See
                // LaunchAtLoginModel.
                Toggle("Start PUSH at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                .task { await launchAtLogin.loadIfNeeded() }
            }

            Section("Hotkey") {
                Picker("Push-to-talk key", selection: $appState.selectedHotkey) {
                    ForEach(AppState.Hotkey.allCases) { hotkey in
                        Text(hotkey.displayName).tag(hotkey)
                    }
                }

                Toggle("Enable hotkey", isOn: $appState.hotkeyEnabled)
                Toggle("Play sound when recording starts", isOn: $appState.playSoundOnStart)
                Picker("While dictating", selection: $appState.mediaBehavior) {
                    ForEach(MediaBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }

                Text("Lowers output volume while recording, then restores it.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Press Esc while recording to cancel without inserting text.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Formatting") {
                Toggle("Double space after sentences", isOn: $appState.doubleSpaceAfterSentence)

                Toggle("Act on spoken corrections", isOn: $appState.resolveSelfCorrections)

                Text("Say \"the red car, I mean the blue car\" and only \"the blue car\" is pasted. Recognises \"I mean\", \"no wait\", \"make that\", \"scratch that\" and similar. Ambiguous words like \"sorry\" and \"actually\" are ignored on purpose — they're too often ordinary speech, and a wrong guess deletes words you meant to keep.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Pill") {
                Picker("Position", selection: $appState.pillPosition) {
                    ForEach(AppState.PillPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                Text("At the top the pill hangs off the screen edge under the notch, so a live transcript sits where you're already reading. At the bottom it floats as a capsule, out of the way.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Live Preview") {
                Toggle("Show text in the pill as you speak", isOn: $appState.showLivePreview)
                    .disabled(!supportsLivePreview)

                Picker("Size", selection: $appState.previewSize) {
                    ForEach(AppState.PreviewSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!supportsLivePreview || !appState.showLivePreview)

                Text(supportsLivePreview
                     ? "Rough transcript, about two seconds behind you. The final text is cleaned up before it's inserted."
                     : "Only Parakeet Streaming transcribes while you speak — switch to it above to use the live preview.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    /// Snapshot of the filesystem check — kept in @State so delete/download
    /// actually refresh the view (a computed property wouldn't re-render).
    @State private var isDownloaded = false

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
        case .parakeetUnified:
            return ParakeetUnifiedEngine.modelDirectory
        case .parakeetStreaming:
            return ParakeetStreamingEngine.modelDirectory
        case .whisperKit:
            return WhisperEngine.modelFolderURL(for: selectedModel)
        }
    }

    private static func checkDownloaded(_ model: AppState.WhisperModel) -> Bool {
        switch model.engineType {
        case .moonshine:
            return MoonshineEngine.isModelDownloaded(model) // Tiny is bundled → true
        case .parakeet:
            return ParakeetEngine.isModelDownloaded()
        case .parakeetUnified:
            return ParakeetUnifiedEngine.isModelDownloaded()
        case .parakeetStreaming:
            return ParakeetStreamingEngine.isModelDownloaded()
        case .whisperKit:
            return WhisperEngine.isModelDownloaded(model)
        }
    }

    /// Load the model and swap it in as the active one, surfacing errors inline.
    private func activate(_ model: AppState.WhisperModel) {
        Task {
            do {
                try await ModelLoader.activate(model)
            } catch {
                downloadError = error.localizedDescription
            }
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
                        Text("PUSH keeps using \(appState.activeModel.displayName) until this model is downloaded.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            isDownloaded = Self.checkDownloaded(selectedModel)
        }
        .onChange(of: appState.selectedWhisperModel) { _, newModel in
            downloadError = nil
            isDownloaded = Self.checkDownloaded(newModel)
            // Swap immediately when the model is already on disk; otherwise the
            // user downloads explicitly and the swap happens after that.
            if isDownloaded {
                activate(newModel)
            }
        }
    }

    /// Rough on-disk sizes used to derive download progress (engines don't report it).
    private static func expectedSize(of model: AppState.WhisperModel) -> Double {
        switch model {
        case .base: return 150_000_000
        case .small: return 250_000_000
        case .whisperLargeV3Turbo: return 632_000_000
        case .moonshineTiny: return 45_000_000
        case .parakeetV2: return 400_000_000
        case .parakeetUnified, .parakeetStreaming: return 600_000_000
        }
    }

    private func downloadModel() {
        let model = appState.selectedWhisperModel
        let folder = modelFolderPath
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Downloading..."
        downloadError = nil
        Task {
            // Poll the download directory for coarse progress.
            let expected = Self.expectedSize(of: model)
            let pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    let progress = min(Self.directorySize(at: folder) / expected, 0.95)
                    await MainActor.run {
                        downloadProgress = progress
                        if progress > 0.01 {
                            downloadStatus = "Downloading... \(Int(progress * 100))%"
                        }
                    }
                }
            }
            do {
                // Engines download on load; activate also swaps it in and warms up.
                try await ModelLoader.activate(model)
                pollTask.cancel()
                downloadProgress = 1.0
                downloadStatus = "Complete!"
            } catch {
                pollTask.cancel()
                downloadError = error.localizedDescription
            }
            isDownloading = false
            isDownloaded = Self.checkDownloaded(model)
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
        let urlToDelete = modelFolderPath

        do {
            if FileManager.default.fileExists(atPath: urlToDelete.path) {
                try FileManager.default.removeItem(at: urlToDelete)
            }
            // Deleting the model that's currently serving: unload it too, so the
            // UI doesn't claim a model that no longer exists on disk.
            if model == appState.activeModel {
                Task { await ModelLoader.deactivate() }
            }
        } catch {
            downloadError = "Failed to delete: \(error.localizedDescription)"
        }
        isDownloaded = Self.checkDownloaded(model)
    }
}

// MARK: - Dictionary Settings

struct DictionarySettingsView: View {
    @ObservedObject private var store = CorrectionsStore.shared
    @State private var newWrong: String = ""
    @State private var newRight: String = ""
    @State private var newContextual: Bool = false
    @State private var newEntity: String = ""
    /// True once the user changes the mode control by hand, so auto-defaulting
    /// (Context for common words) stops overriding their choice.
    @State private var modeManuallySet: Bool = false

    private var canAdd: Bool {
        !newWrong.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newRight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var wrongIsCommonWord: Bool { WordChecker.isCommonWord(newWrong) }

    var body: some View {
        Form {
            Section("Add a Correction") {
                HStack(spacing: 8) {
                    TextField("Heard as (e.g. Hammer)", text: $newWrong)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onChange(of: newWrong) { _, value in
                            // Default new common-word entries to Context (safer),
                            // unless the user already picked a mode themselves.
                            if !modeManuallySet {
                                newContextual = WordChecker.isCommonWord(value)
                            }
                        }
                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                    TextField("Should be (e.g. Hamer)", text: $newRight)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    Button("Add") {
                        store.addCorrection(
                            wrong: newWrong,
                            right: newRight,
                            kind: newContextual ? .contextual : .always,
                            entity: newContextual ? newEntity : nil
                        )
                        newWrong = ""
                        newRight = ""
                        newEntity = ""
                        newContextual = false
                        modeManuallySet = false
                    }
                    .disabled(!canAdd)
                }

                Picker("Replace", selection: Binding(
                    get: { newContextual },
                    set: { newContextual = $0; modeManuallySet = true }
                )) {
                    Text("Always").tag(false)
                    Text("Only in context").tag(true)
                }
                .pickerStyle(.segmented)

                if newContextual {
                    TextField("What is it? (e.g. a person named Hamer)", text: $newEntity)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }

                if wrongIsCommonWord && !newContextual {
                    Label("“\(newWrong)” is also a common word — “Only in context” avoids over-correcting it.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Text(newContextual
                     ? "Replaced only when the surrounding words suggest the entity is meant."
                     : "Replaced every time it’s heard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Your Dictionary") {
                if store.corrections.isEmpty {
                    Text("No corrections yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach($store.corrections) { $correction in
                        let entityText = Binding<String>(
                            get: { correction.entity ?? "" },
                            set: { $correction.entity.wrappedValue = $0.isEmpty ? nil : $0 }
                        )
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                TextField("", text: $correction.wrong)
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("", text: $correction.right)
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
                                Picker("", selection: $correction.kind) {
                                    Text("Always").tag(CorrectionsStore.Correction.Kind.always)
                                    Text("Context").tag(CorrectionsStore.Correction.Kind.contextual)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .fixedSize()
                                .help("Always replace, or only when the context fits")
                                Button {
                                    store.remove(correction)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                                .help("Remove this correction")
                            }
                            if correction.kind == .contextual {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    TextField("what is it? (e.g. a person named Hamer)", text: entityText)
                                        .textFieldStyle(.roundedBorder)
                                        .labelsHidden()
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Text("Switch any row between Always and Context, edit inline, or remove with the trash icon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("PUSH")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion)")
                .foregroundColor(.secondary)

            Text("Voice to text with offline AI")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("Hold \(appState.selectedHotkey.displayName) to speak · Esc to cancel")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
#endif
