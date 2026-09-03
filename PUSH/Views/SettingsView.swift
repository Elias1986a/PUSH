import SwiftUI
import AppKit
import Combine
import PUSHCore

/// The settings window.
///
/// A sidebar rather than a tab bar: the four tabs this replaced put eight
/// unrelated sections behind "General" — hotkey, sound, other apps' audio,
/// formatting, iCloud, pill, live preview, wake word — which is more than a tab
/// label can honestly describe and more than fits without scrolling.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var pane: Pane = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general, dictation, text, pill, teleprompter, models, dictionary

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .dictation: return "Dictation"
            case .text: return "Text"
            case .pill: return "Pill"
            case .teleprompter: return "Teleprompter"
            case .models: return "Models"
            case .dictionary: return "Dictionary"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .dictation: return "mic"
            case .text: return "text.alignleft"
            case .pill: return "capsule"
            case .teleprompter: return "text.viewfinder"
            case .models: return "cpu"
            case .dictionary: return "character.book.closed"
            }
        }
    }

    var body: some View {
        // A plain split rather than NavigationSplitView: inside a `Settings`
        // scene that container treats a frame as advisory and sizes itself from
        // content, which opened the window at 450×480, then 720×720, then
        // 900×696 across three attempts. A settings window has exactly one
        // right size, so it is stated here and nothing negotiates it.
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(width: 524)
        }
        .frame(width: 720, height: 640)
        .navigationTitle(pane.title)
    }

    private var sidebar: some View {
        List(Pane.allCases, selection: $pane) { item in
            Label(item.title, systemImage: item.symbol)
                .tag(item)
        }
        .listStyle(.sidebar)
        .frame(width: 196)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general:
            GeneralSettingsView().environmentObject(appState)
        case .dictation:
            DictationSettingsView().environmentObject(appState)
        case .text:
            TextSettingsView().environmentObject(appState)
        case .pill:
            PillSettingsView().environmentObject(appState)
        case .teleprompter:
            TeleprompterSettingsView()
        case .models:
            ModelsSettingsView().environmentObject(appState)
        case .dictionary:
            DictionarySettingsView()
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var launchAtLogin = LaunchAtLoginModel()
    @StateObject private var permissions = PermissionsModel()
    @ObservedObject private var updater = UpdaterManager.shared

    /// Sparkle owns the stored value; this mirrors it only for the toggle's
    /// binding, and writes straight back through on change.
    @State private var checksAutomatically = UpdaterManager.shared.automaticallyChecksForUpdates

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 15) {
                    // NSApp's own icon, not a bundled asset: Bundle.module
                    // resource lookup crashes in distribution builds.
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PUSH")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Offline voice to text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(updater.isCheckingForUpdates ? "Checking…" : "Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canBeInvoked)
                }
                .padding(.vertical, 4)
            }

            Section("Startup") {
                // Not LaunchAtLogin.Toggle: its binding reads
                // SMAppService.status synchronously from the view body, which
                // blocks the main thread ~61ms per render pass. See
                // LaunchAtLoginModel.
                Toggle("Open PUSH at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                .task { await launchAtLogin.loadIfNeeded() }

                Toggle("Check for updates automatically", isOn: $checksAutomatically)
                    .onChange(of: checksAutomatically) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }
            }

            Section("iCloud") {
                Toggle("Sync settings and dictionary across my Macs", isOn: $appState.iCloudSyncEnabled)

                Text("Uses the iCloud account this Mac is signed into — no separate login. Dictionary entries are merged, never replaced. The pill's position stays per-Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    reason: "PUSH cannot hear you without it.",
                    status: permissions.microphone,
                    openSettings: permissions.openSystemSettings
                )
                PermissionRow(
                    title: "Accessibility",
                    reason: "Needed for the push-to-talk key and for pasting text.",
                    status: permissions.accessibility,
                    openSettings: permissions.openSystemSettings
                )
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: permissions.refresh)
        // The round trip to System Settings and back is the whole point: macOS
        // never tells us the answer changed, so coming back to the front is the
        // signal.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }
}

/// One permission's state. macOS never tells an app that its permissions
/// changed, so the reason line and button only appear while something is
/// actually missing — see `PermissionsModel` for when this re-reads.
private struct PermissionRow: View {
    let title: String
    let reason: String
    let status: PermissionsModel.Status
    let openSettings: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !status.isGranted {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if status.isGranted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Allowed")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else {
                Button("Open System Settings…", action: openSettings)
            }
        }
    }
}

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

// MARK: - Text

struct TextSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Formatting") {
                Toggle("Double space after sentences", isOn: $appState.doubleSpaceAfterSentence)
            }

            Section("Spoken corrections") {
                Toggle("Act on corrections you say out loud", isOn: $appState.resolveSelfCorrections)

                Text("Say “the red car, I mean the blue car” and only “the blue car” is pasted. Also recognises “no wait”, “make that” and “scratch that”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Showing it beats describing it: the old copy spent a
                // paragraph on what one example makes obvious.
                VStack(alignment: .leading, spacing: 8) {
                    Text("You say")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Book the table for ")
                        + Text("six").strikethrough().foregroundColor(.secondary)
                        + Text(", I mean eight")

                    Divider()

                    Text("PUSH inserts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Book the table for eight")
                }
                .padding(.vertical, 4)

                Text("Words like “sorry” and “actually” are ignored on purpose — too often ordinary speech, and a wrong guess deletes words you meant to keep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pill

struct PillSettingsView: View {
    @EnvironmentObject var appState: AppState

    /// Keyed off the *selected* model rather than the active one, so the toggle
    /// greys out the moment you pick another model instead of waiting for the
    /// swap to finish loading.
    private var supportsLivePreview: Bool {
        appState.selectedWhisperModel.engineType == .parakeetStreaming
    }

    var body: some View {
        Form {
            Section("Position") {
                HStack(spacing: 26) {
                    Spacer()
                    ForEach(AppState.PillPosition.allCases) { position in
                        PillPositionThumbnail(
                            position: position,
                            isSelected: appState.pillPosition == position
                        )
                        .onTapGesture { appState.pillPosition = position }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)

                Text("At the bottom the pill floats as a capsule, out of the way. At the top it hangs off the screen edge under the notch, where you are already reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Live preview") {
                Toggle("Show text in the pill as you speak", isOn: $appState.showLivePreview)
                    .disabled(!supportsLivePreview)

                Picker("Text size", selection: $appState.previewSize) {
                    ForEach(AppState.PreviewSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!supportsLivePreview || !appState.showLivePreview)

                Text(supportsLivePreview
                     ? "A rough transcript, about two seconds behind you — the final text is cleaned up before it is inserted."
                     : "Only Parakeet Streaming transcribes while you speak, and \(appState.selectedWhisperModel.shortName) is selected. Switch in Models to turn this on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A little screen showing where the pill sits. Cheaper to understand than the
/// paragraph it replaced, and it is the one place the brand's pulse colour
/// appears outside the pill itself.
private struct PillPositionThumbnail: View {
    let position: AppState.PillPosition
    let isSelected: Bool

    private static let pulse = Color(red: 0.69, green: 1.0, blue: 0.0)
    private static let desktop = Color(red: 0.43, green: 0.49, blue: 0.55)

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Rectangle().fill(Self.desktop)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 12)
                    Spacer(minLength: 0)
                }

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 132, height: 60)
            }
            .frame(width: 176, height: 112)
            .overlay(alignment: position == .top ? .top : .bottom) {
                pill
                    .padding(.bottom, position == .top ? 0 : 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.12),
                                  lineWidth: isSelected ? 2.5 : 0.5)
            }

            Text(position.displayName)
                .font(.caption)
                .fontWeight(isSelected ? .medium : .regular)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var pill: some View {
        if position == .top {
            waveform
                .frame(width: 96, height: 20)
                .background(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 8
                    )
                    .fill(Color(white: 0.11))
                )
        } else {
            waveform
                .frame(width: 84, height: 22)
                .background(Capsule().fill(Color(white: 0.11).opacity(0.92)))
        }
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach([CGFloat(6), 10, 7, 11, 5], id: \.self) { height in
                Capsule()
                    .fill(Self.pulse)
                    .frame(width: 2.5, height: height)
            }
        }
    }
}

// MARK: - Models

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState

    /// Snapshot of the filesystem check for every model — kept in @State so
    /// download/delete actually refresh the view, and so the list does not stat
    /// four directories on every render pass.
    @State private var downloaded: Set<AppState.WhisperModel> = []
    @State private var downloadingModel: AppState.WhisperModel?
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus: String = ""
    @State private var downloadError: String?
    @State private var appleStatus: AppleSpeechAssetStatus = .unknown
    @State private var storageBytes: Double = 0

    /// Measured on-disk size per model, filled by `refreshStorage`. Empty until
    /// the first walk finishes, which is why `metaLine` falls back to the
    /// download estimate rather than rendering a confident "Zero KB".
    @State private var modelBytes: [AppState.WhisperModel: Double] = [:]

    /// Measured size of each Nemotron vocab build, keyed by variant.
    @State private var buildBytes: [String: Double] = [:]

    var body: some View {
        Form {
            Section("Speech model") {
                ForEach(AppState.WhisperModel.selectable) { model in
                    modelRow(model)
                }

                Text("Every model runs on this Mac. Nothing you say is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloaded models")
                        Text(storageBytes > 0
                             ? "\(Self.format(bytes: storageBytes)) in Application Support"
                             : "Nothing downloaded yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: ParakeetUnifiedEngine.modelDirectory
                                .deletingLastPathComponent().path
                        )
                    }
                    .disabled(storageBytes == 0)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshDownloaded()
            refreshAppleStatus()
            refreshStorage()
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func modelRow(_ model: AppState.WhisperModel) -> some View {
        let isSelected = appState.selectedWhisperModel == model

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(model.shortName)
                        .fontWeight(.medium)
                    if let badge = model.badge {
                        Text(badge)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(model.modelDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(metaLine(for: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(buildBreakdown(for: model), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }

                if Self.showsLanguagePicker(for: model, selectedModel: appState.selectedWhisperModel) {
                    DictationLanguagePicker(
                        model: model,
                        onModelsChanged: {
                            refreshDownloaded()
                            refreshStorage()
                            // Apple installs its assets per locale, so the
                            // answer to "is this installed" changes with the
                            // language. Without this the row keeps showing the
                            // status of whichever locale was current on appear.
                            refreshAppleStatus()
                        },
                        reload: { willDownload in
                            await reloadForLanguage(model, willDownload: willDownload)
                        })
                    .padding(.top, 2)
                }

                if downloadingModel == model {
                    if downloadProgress > 0 {
                        ProgressView(value: downloadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text(downloadStatus.isEmpty ? "Downloading…" : downloadStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isSelected, let downloadError {
                    Text(downloadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            trailing(for: model)
                .padding(.top, 2)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { select(model) }
    }

    @ViewBuilder
    private func trailing(for model: AppState.WhisperModel) -> some View {
        if downloadingModel == model {
            EmptyView()
        } else if showsActiveBadge(for: model) {
            // The engine that is loaded says so, whichever engine it is. Apple
            // Speech used to be answered by a short-circuit above this check, so
            // the one engine needing no download was also the only one that
            // never said "Active": it sat reading "Installs on first use" while
            // it was loaded and transcribing, which reads as "not working yet".
            statusBadge(icon: "checkmark.circle.fill", color: .green, text: "Active")
        } else if model == .appleSpeech {
            // No download button: these assets belong to the OS. A progress bar
            // we neither drive nor can cancel would be a fiction, so this
            // reports the system's own state instead.
            statusBadge(icon: appleStatusIcon, color: appleStatusColor, text: appleStatusLabel)
        } else if downloaded.contains(model) {
            Button("Delete") { deleteModel(model) }
                .foregroundStyle(.red)
        } else {
            Button("Download") { downloadModel(model) }
                .disabled(downloadingModel != nil)
        }
    }

    /// Whether `model` is the engine currently serving dictation.
    ///
    /// Apple Speech has no files of ours, so `downloaded` is the wrong question
    /// for it — but "still installing" is worth saying in preference to
    /// "Active", since that install is the one thing that would stop it working.
    private func showsActiveBadge(for model: AppState.WhisperModel) -> Bool {
        guard model == appState.activeModel else { return false }
        if model == .appleSpeech { return appleStatus != .installing }
        return downloaded.contains(model)
    }

    private func statusBadge(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    /// One line per Nemotron build actually on disk, shown only when there are
    /// two of them.
    ///
    /// Nemotron ships one ~600 MB build per language group, so picking Arabic
    /// while holding the Latin build silently doubles what the engine occupies.
    /// A lone "1.28 GB" hides that a second download ever happened — and hides
    /// that Delete reclaims both. With one build the total already says it, and
    /// a sub-line repeating itself is noise.
    private func buildBreakdown(for model: AppState.WhisperModel) -> [String] {
        guard model == .nemotronMultilingual else { return [] }
        let present = NemotronMultilingualEngine.buildVariants.compactMap { variant in
            (buildBytes[variant] ?? 0) > 0 ? (variant, buildBytes[variant]!) : nil
        }
        guard present.count > 1 else { return [] }
        return present.map { "\(Self.buildName($0.0)) · \(Self.format(bytes: $0.1))" }
    }

    /// Named by what the build can transcribe, not by the language that
    /// happened to pull it: the second build serves Arabic, Chinese, Japanese,
    /// Russian and every other non-Latin script, so calling it "Arabic" would
    /// suggest deleting it costs only Arabic.
    private static func buildName(_ variant: String) -> String {
        variant == "latin" ? "Latin-script languages" : "All other languages"
    }

    private func metaLine(for model: AppState.WhisperModel) -> String {
        if model == .appleSpeech {
            return "No download · managed by macOS"
        }
        let isDownloaded = downloaded.contains(model)
        let state = isDownloaded ? "on this Mac" : "not downloaded"

        // Once it is on disk, say what is actually there. `downloadSizeLabel` is
        // one build's download, and Nemotron ships one per language group: a
        // user who has picked Arabic as well as Spanish has two, so the constant
        // described a 1.2 GB row as 600 MB. Before the download that constant is
        // still the right number — it is what the user is about to fetch — and
        // it also stands in until the first size walk finishes.
        let measured = isDownloaded
            ? modelBytes[model].flatMap { $0 > 0 ? Self.format(bytes: $0) : nil }
            : nil
        let size = measured ?? model.downloadSizeLabel
        // Trimming the size out of `modelDescription` also removed the only
        // place that said Streaming and Unified are one download. Deleting
        // either removes both, so the row has to admit it.
        if model == .parakeetStreaming || model == .parakeetUnified {
            let other: AppState.WhisperModel = model == .parakeetStreaming ? .parakeetUnified : .parakeetStreaming
            if AppState.WhisperModel.selectable.contains(other) {
                return "\(size) · shared with \(other.shortName) · \(state)"
            }
        }
        return "\(size) · \(state)"
    }

    // MARK: Language

    /// Whether `model`'s row should carry a dictation-language picker.
    ///
    /// Two conditions, and both earn their place. A picker under an engine that
    /// cannot take a language is a lie — the Parakeet exports are English-only
    /// by construction, and offering a choice there would be a control that
    /// silently does nothing. A picker under *every* row, meanwhile, is noise:
    /// the list is five rows of model comparison, and four popup buttons the
    /// user is not currently using bury the comparison they came to read.
    ///
    /// Keyed on `selectedWhisperModel` (the preference the row's radio button
    /// draws) rather than `activeModel` (what is loaded right now), so the
    /// picker appears under the row that looks chosen. They differ while a newly
    /// picked model is still downloading — precisely when the user is most
    /// likely to want to set its language.
    ///
    /// Internal rather than private so the tests can pin this decision; it is
    /// not part of any view's `body`, which is why it can be pinned at all.
    static func showsLanguagePicker(
        for model: AppState.WhisperModel,
        selectedModel: AppState.WhisperModel
    ) -> Bool {
        model == selectedModel && model.supportsLanguageSelection
    }

    // MARK: Apple asset status

    private var appleStatusLabel: String {
        switch appleStatus {
        case .unknown: return "Checking…"
        case .installed: return "Ready"
        case .willInstall: return "Installs on first use"
        case .installing: return "Installing…"
        case .unsupported: return "Not available"
        }
    }

    private var appleStatusIcon: String {
        switch appleStatus {
        case .installed: return "checkmark.circle.fill"
        case .installing: return "arrow.down.circle"
        case .willInstall: return "icloud.and.arrow.down"
        case .unknown: return "ellipsis.circle"
        case .unsupported: return "exclamationmark.triangle"
        }
    }

    private var appleStatusColor: Color {
        switch appleStatus {
        case .installed: return .green
        case .unsupported: return .orange
        case .unknown, .willInstall, .installing: return .secondary
        }
    }

    /// Ask the system what state its speech assets are in. Only meaningful for
    /// `.appleSpeech`, which `selectable` already filters out below macOS 26.
    private func refreshAppleStatus() {
        guard AppState.WhisperModel.selectable.contains(.appleSpeech) else { return }
        guard #available(macOS 26, *) else {
            appleStatus = .unsupported
            return
        }
        appleStatus = .unknown
        Task {
            let status = await AppleSpeechEngine.installStatus()
            await MainActor.run {
                switch status {
                case .installed: appleStatus = .installed
                case .downloading: appleStatus = .installing
                case .supported: appleStatus = .willInstall
                case .unsupported: appleStatus = .unsupported
                @unknown default: appleStatus = .unknown
                }
            }
        }
    }

    // MARK: Selection

    /// Picking a row records the preference; the swap only happens once the
    /// model is actually on disk, so dictation keeps working meanwhile.
    private func select(_ model: AppState.WhisperModel) {
        guard appState.selectedWhisperModel != model else { return }
        downloadError = nil
        appState.selectedWhisperModel = model
        if downloaded.contains(model) || model == .appleSpeech {
            activate(model)
        }
    }

    private func activate(_ model: AppState.WhisperModel) {
        Task {
            do {
                try await ModelLoader.activate(model)
                // Cleared on success, not merely when the next attempt starts.
                // A failed load followed by a successful retry otherwise leaves
                // the red text sitting under a row that is simultaneously
                // showing the green "Active" badge — the state the first
                // multilingual download actually reached, where a transient
                // mid-download failure was still on screen minutes after the
                // model had loaded and was transcribing fine.
                downloadError = nil
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }

    /// Runs a language change with the row's own progress bar and error line.
    ///
    /// Choosing a language can fetch a second ~600 MB build with nobody having
    /// pressed Download — picking Arabic while the latin build is resident does
    /// exactly that — and until this existed the app just went quiet for the
    /// length of the transfer. No bar, no percentage, and on failure nothing at
    /// all, because the reload swallowed its own error. Measured at 43 seconds
    /// of silence on a fast connection; minutes on a slow one, which reads as a
    /// hung app rather than a download.
    ///
    /// Progress is measured against a baseline taken before the transfer starts,
    /// not against the folder's absolute size: the folder already holds the
    /// build being switched away from, so an absolute measure would sit at 100%
    /// from the first sample and never move.
    private func reloadForLanguage(_ model: AppState.WhisperModel, willDownload: Bool) async {
        downloadError = nil

        // A same-build switch is a prompt swap. Nothing to show, but a failure
        // still has to surface rather than disappear.
        guard willDownload, let folder = Self.folder(for: model) else {
            do {
                try await ModelLoader.reloadForLanguageChange(model)
            } catch {
                downloadError = error.localizedDescription
            }
            return
        }

        let language = appState.language(for: model).displayName
        downloadingModel = model
        downloadProgress = 0
        downloadStatus = "Downloading \(language)…"

        let expected = Self.expectedSize(of: model)
        let baseline = await Task.detached(priority: .utility) {
            Self.directorySize(at: folder)
        }.value

        let pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let onDisk = await Task.detached(priority: .utility) {
                    Self.directorySize(at: folder)
                }.value
                let progress = min(max(0, onDisk - baseline) / expected, 0.95)
                await MainActor.run {
                    downloadProgress = progress
                    if progress > 0.01 {
                        downloadStatus = "Downloading \(language)… \(Int(progress * 100))%"
                    }
                }
            }
        }

        do {
            try await ModelLoader.reloadForLanguageChange(model)
            pollTask.cancel()
            downloadProgress = 1.0
            downloadStatus = "Complete!"
        } catch {
            pollTask.cancel()
            downloadError = error.localizedDescription
        }
        downloadingModel = nil
    }

    // MARK: Filesystem

    private nonisolated static func folder(for model: AppState.WhisperModel) -> URL? {
        switch model.engineType {
        case .parakeet: return ParakeetEngine.modelDirectory
        case .parakeetUnified: return ParakeetUnifiedEngine.modelDirectory
        case .parakeetStreaming: return ParakeetStreamingEngine.modelDirectory
        // The repo root, covering both vocab builds — a user who has dictated in
        // two language groups has two of them down.
        case .nemotronMultilingual: return NemotronMultilingualEngine.modelDirectory
        case .appleSpeech: return nil  // the OS owns these; nothing of ours to show
        }
    }

    private static func checkDownloaded(_ model: AppState.WhisperModel) -> Bool {
        switch model.engineType {
        case .parakeet: return ParakeetEngine.isModelDownloaded()
        case .parakeetUnified: return ParakeetUnifiedEngine.isModelDownloaded()
        case .parakeetStreaming: return ParakeetStreamingEngine.isModelDownloaded()
        case .nemotronMultilingual: return NemotronMultilingualEngine.isModelDownloaded()
        case .appleSpeech:
            // Nothing for us to download — the system installs on demand.
            return true
        }
    }

    private func refreshDownloaded() {
        downloaded = Set(
            AppState.WhisperModel.selectable.filter { $0 != .appleSpeech && Self.checkDownloaded($0) }
        )
    }

    /// Walks the model directories, so it runs off the main thread — blocking it
    /// is how this app loses its event tap.
    private func refreshStorage() {
        // Deduplicated: Parakeet Streaming and Parakeet Unified are the same
        // weights in the same directory, so summing per-model counted 1.21 GB
        // twice and reported 2.41.
        let foldersByModel: [AppState.WhisperModel: URL] = Dictionary(
            uniqueKeysWithValues: AppState.WhisperModel.selectable.compactMap { model in
                Self.folder(for: model).map { (model, $0.standardizedFileURL) }
            })
        let builds = NemotronMultilingualEngine.buildVariants.map {
            ($0, NemotronMultilingualEngine.buildDirectory($0).standardizedFileURL)
        }
        let folders = Set(foldersByModel.values).union(builds.map(\.1))
        Task {
            // One walk per distinct folder, reused for both the total and the
            // per-row figure — the rows and the Storage line must not be able
            // to disagree about the same bytes.
            let sizes = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: folders.map { ($0, Self.directorySize(at: $0)) })
            }.value
            await MainActor.run {
                // Summed over the model folders only: the build directories
                // live inside the Nemotron folder, so counting both would
                // report its bytes twice.
                storageBytes = Set(foldersByModel.values).compactMap { sizes[$0] }.reduce(0, +)
                modelBytes = foldersByModel.compactMapValues { sizes[$0] }
                buildBytes = Dictionary(uniqueKeysWithValues:
                    builds.compactMap { variant, url in sizes[url].map { (variant, $0) } })
            }
        }
    }

    private static func format(bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Rough on-disk sizes used to derive download progress (engines don't report it).
    private static func expectedSize(of model: AppState.WhisperModel) -> Double {
        switch model {
        case .parakeetV2: return 400_000_000
        case .parakeetUnified, .parakeetStreaming, .nemotronMultilingual: return 600_000_000
        case .appleSpeech: return 0  // never downloaded through us
        }
    }

    private nonisolated static func directorySize(at url: URL) -> Double {
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

    // MARK: Download / delete

    private func downloadModel(_ model: AppState.WhisperModel) {
        guard let folder = Self.folder(for: model) else { return }
        // Downloading is also choosing: nobody fetches 600 MB they don't intend
        // to use.
        appState.selectedWhisperModel = model
        downloadingModel = model
        downloadProgress = 0
        downloadStatus = "Downloading…"
        downloadError = nil

        Task {
            // Poll the download directory for coarse progress.
            let expected = Self.expectedSize(of: model)
            let pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    let onDisk = await Task.detached(priority: .utility) {
                        Self.directorySize(at: folder)
                    }.value
                    let progress = min(onDisk / expected, 0.95)
                    await MainActor.run {
                        downloadProgress = progress
                        if progress > 0.01 {
                            downloadStatus = "Downloading… \(Int(progress * 100))%"
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
            downloadingModel = nil
            refreshDownloaded()
            refreshStorage()
        }
    }

    private func deleteModel(_ model: AppState.WhisperModel) {
        guard let folder = Self.folder(for: model) else { return }
        downloadError = nil

        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            // Compare FOLDERS, not models. Streaming and Unified share one
            // directory, so deleting Streaming while Unified is serving pulls
            // the active model's files out from under it — and `model ==
            // activeModel` is false in exactly that case.
            if let activeFolder = Self.folder(for: appState.activeModel),
               activeFolder.standardizedFileURL == folder.standardizedFileURL {
                Task { await ModelLoader.deactivate() }
            }
        } catch {
            downloadError = "Failed to delete: \(error.localizedDescription)"
        }
        refreshDownloaded()
        refreshStorage()
    }
}

// MARK: - Dictation language

/// The language control that sits inside the selected engine's row in Models.
///
/// Its own view rather than a `@ViewBuilder` on `ModelsSettingsView` for one
/// concrete reason: the language list is resolved asynchronously and has to be
/// held in `@State`, and there is exactly one picker on screen at a time (the
/// selected engine's). A dictionary of per-model lists on the parent would
/// carry four dead entries and would still need re-resolving by hand when the
/// selection moved; here SwiftUI's own view identity does that work.
struct DictationLanguagePicker: View {
    let model: AppState.WhisperModel

    /// Called once a language change has finished loading. Choosing a language
    /// can pull a ~600 MB build without anyone pressing Download, and the row's
    /// "on this Mac" line and the Storage total would otherwise both go stale.
    var onModelsChanged: () -> Void = {}

    /// Performs the reload. `willDownload` says whether it is about to pull
    /// another ~600 MB build.
    ///
    /// Supplied by the parent rather than run here because the progress bar and
    /// the error line belong to the model row, not to this control — and
    /// because the flag matters: a same-build language change is a prompt swap
    /// that finishes in about 0.15s, and putting a progress bar on that would
    /// only flicker.
    var reload: @MainActor (_ willDownload: Bool) async -> Void = { _ in }

    @EnvironmentObject private var appState: AppState

    /// `nil` means "not asked yet", which is a genuinely different state from
    /// "this engine offers nothing" and must not draw the same UI. Collapsing
    /// them made Apple Speech flash "no languages" on every appearance while
    /// the OS query was in flight.
    @State private var languages: [DictationLanguage]?

    /// Whether the language now selected still needs its model build fetched.
    @State private var needsAnotherDownload = false

    /// Bumped after a reload. Crossing vocab groups swaps in a build with a
    /// different `prompt_dictionary`, so the list of offered languages is not
    /// the same list it was a moment ago.
    @State private var reloadToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Language")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Language", selection: selection) {
                    ForEach(options) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)
                // Disabled rather than hidden when there is nothing to choose
                // from: a control that vanishes reads as a bug, and the note
                // below only makes sense next to the thing it is explaining.
                .disabled(hasNoChoice)
            }

            if let unavailableNote {
                note(unavailableNote)
            } else if needsAnotherDownload {
                note(extraDownloadNote)
            }
        }
        .task(id: listKey) { await resolveLanguages() }
    }

    /// Matches `TeleprompterSettingsView`'s "needs the Parakeet model" note
    /// exactly — same orange, same triangle, same caption size. Two panes
    /// describing the same situation (a model that isn't there yet) in two
    /// different visual languages would read as two different problems.
    private func note(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    // MARK: Contents

    private var current: DictationLanguage { appState.language(for: model) }

    private var hasNoChoice: Bool { (languages ?? []).isEmpty }

    /// What the popup lists.
    ///
    /// Never empty: a `Picker` whose selection is absent from its content draws
    /// a blank button, so the fallback while the list is unknown or empty is the
    /// saved choice on its own — disabled, but at least naming the language the
    /// engine will actually use.
    ///
    /// The same reasoning covers a saved language the engine no longer offers
    /// (a preference from another build, or a dependency bump that changed the
    /// list): it is appended rather than dropped, because silently showing blank
    /// leaves the user unable to see — or move off — what they are set to.
    private var options: [DictationLanguage] {
        guard let languages, !languages.isEmpty else { return [current] }
        guard !languages.contains(current) else { return languages }
        return (languages + [current]).sorted()
    }

    private var selection: Binding<DictationLanguage> {
        // Hand-built rather than bound to a stored property: the preference is
        // keyed by engine, so there is no single property to bind to.
        // `AppState.setLanguage` publishes the change itself, which is what
        // makes this redraw.
        Binding(get: { current }, set: { choose($0) })
    }

    /// Shown in place of a usable picker when the engine can't name its
    /// languages yet.
    private var unavailableNote: String? {
        guard let languages, languages.isEmpty else { return nil }
        switch model {
        case .nemotronMultilingual:
            // `supportedLanguages()` reads the loaded model's own prompt
            // dictionary and deliberately has no hardcoded fallback, so an
            // undownloaded engine has genuinely nothing to offer.
            return "Download the model to see its languages."
        case .appleSpeech:
            return "macOS hasn't offered any dictation languages yet."
        case .parakeetV2, .parakeetUnified, .parakeetStreaming:
            // Unreachable — `showsLanguagePicker` keeps the English engines out
            // of this view. Listed rather than defaulted so adding an engine is
            // a compile error here instead of a wrong sentence at runtime.
            return nil
        }
    }

    private var extraDownloadNote: String {
        "\(current.displayName) needs a different model build. "
            + "That's another \(model.downloadSizeLabel) to download."
    }

    // MARK: Resolving the list

    /// Re-resolve whenever the running engine changes: downloading Nemotron
    /// from the row's own Download button is what turns its empty list into a
    /// real one, and that arrives as an `activeModel`/`isModelReady` change.
    private var listKey: String {
        "\(appState.activeModel.rawValue)|\(appState.isModelReady)|\(reloadToken)"
    }

    /// Each engine reports only its own languages. Never merged: Nemotron's six
    /// or so latin-build languages and Apple's forty-five are different sets,
    /// and a combined list would offer the user languages the engine they are
    /// running cannot transcribe.
    private func resolveLanguages() async {
        let resolved: [DictationLanguage]
        switch model.engineType {
        case .nemotronMultilingual:
            resolved = await NemotronMultilingualEngine.shared.supportedLanguages()
        case .appleSpeech:
            if #available(macOS 26, *) {
                resolved = await AppleSpeechEngine.supportedLanguages()
            } else {
                resolved = []
            }
        case .parakeet, .parakeetUnified, .parakeetStreaming:
            resolved = []
        }
        languages = resolved
        needsAnotherDownload = Self.currentNeedsAdditionalDownload(for: model, language: current)
    }

    // MARK: Choosing

    private func choose(_ language: DictationLanguage) {
        guard language != current else { return }
        appState.setLanguage(language, for: model)

        // Computed here and now, not inside the Task below, because the whole
        // value of this note is that it is on screen *before* the download
        // starts. It is two directory listings — nowhere near the sustained
        // main-thread block that makes macOS disable PUSH's event tap.
        needsAnotherDownload = Self.currentNeedsAdditionalDownload(for: model, language: language)

        guard ModelLoader.languageChangeNeedsReload(
            changed: model,
            activeModel: appState.activeModel,
            isModelReady: appState.isModelReady
        ) else { return }

        // Kicked off and left to run. A settings click must never wait on a
        // model load or an OS asset install: blocking the main thread is how
        // this app loses its CGEvent tap and starts silently dropping hotkey
        // presses. The status the reload writes into `AppState` is already read
        // by the menu bar and the pill, so there is nothing to wait for here.
        let willDownload = needsAnotherDownload

        Task {
            await reload(willDownload)
            // Re-ask rather than assume: the build is on disk now, unless the
            // load failed, in which case the warning is still true.
            needsAnotherDownload = Self.currentNeedsAdditionalDownload(for: model, language: language)
            reloadToken += 1
            onModelsChanged()
        }
    }

    // MARK: The cross-group download warning

    /// Whether choosing `language` will pull another model build.
    ///
    /// Nemotron ships two ~600 MB builds — `latin` (en/es/fr/it/pt/de) and
    /// `multilingual` (everything else) — and the Models row says "Downloaded"
    /// when *either* is present, which is the right answer for a row that asks
    /// one yes/no question about one engine. It is also, on its own, how a user
    /// who has Japanese down picks Spanish and gets several minutes of nothing
    /// happening while the UI insists the model is already there.
    ///
    /// The two on-disk checks are injected rather than called directly so this
    /// decision can be tested against known filesystem states instead of
    /// whatever this machine happens to have downloaded.
    static func needsAdditionalDownload(
        for model: AppState.WhisperModel,
        language: DictationLanguage,
        isEngineDownloaded: () -> Bool,
        isLanguageDownloaded: (String) -> Bool
    ) -> Bool {
        // The only engine with more than one build. Apple's assets are the OS's
        // business and the row already reports their state in its own words.
        guard model == .nemotronMultilingual else { return false }

        // Nothing on disk at all is not a surprise — the row says "not
        // downloaded" and offers a Download button. Warning here as well would
        // put two download notices on the same row and bury the one case that
        // actually catches people out.
        guard isEngineDownloaded() else { return false }

        return !isLanguageDownloaded(language.code)
    }

    /// The live-filesystem form of the above, for the view to call.
    private static func currentNeedsAdditionalDownload(
        for model: AppState.WhisperModel,
        language: DictationLanguage
    ) -> Bool {
        needsAdditionalDownload(
            for: model,
            language: language,
            isEngineDownloaded: { NemotronMultilingualEngine.isModelDownloaded() },
            isLanguageDownloaded: { NemotronMultilingualEngine.isModelDownloaded(for: $0) }
        )
    }
}

// MARK: - Dictionary

struct DictionarySettingsView: View {
    @ObservedObject private var store = CorrectionsStore.shared

    /// A row being typed, held here rather than in the store: `addCorrection`
    /// refuses a half-empty entry, and it is right to — an entry with an empty
    /// "heard as" would match everything, and the dictionary syncs to iCloud.
    /// So the new row is a draft until it has both halves.
    @State private var draft: Draft?
    @FocusState private var draftFieldFocused: Bool
    /// Row order, held still while the list is on screen — see `displayed`.
    @State private var order: [UUID] = []

    private struct Draft {
        var wrong: String = ""
        var right: String = ""
        var contextual: Bool = false
        var entity: String = ""
        /// True once the mode control is changed by hand, so auto-defaulting
        /// (Context for common words) stops overriding that choice.
        var modeManuallySet: Bool = false

        var isComplete: Bool {
            !wrong.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        Form {
            Section("Your dictionary") {
                if let draft {
                    draftRow(draft)
                }

                ForEach(displayed) { correction in
                    // Look the binding back up by id: the display order is not
                    // the storage order, and rows must stay editable.
                    if let index = store.corrections.firstIndex(where: { $0.id == correction.id }) {
                        correctionRow($store.corrections[index])
                    }
                }

                if store.corrections.isEmpty && draft == nil {
                    Text("No corrections yet. Add one with +.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        draft = Draft()
                        draftFieldFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 14)
                    }
                    .disabled(draft != nil)
                    .help("Add a correction")
                    Spacer()
                }

                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshOrder)
        // Ids only: the order settles when entries arrive or leave, never on a
        // keystroke. Editing a row re-stamps `modifiedAt`, and re-sorting on
        // that would slide the row out from under the cursor mid-word.
        .onChange(of: store.corrections.map(\.id)) { _, _ in refreshOrder() }
        .onDisappear(perform: commitDraft)
    }

    /// The rows as drawn: `order` while it holds, with anything it hasn't seen
    /// yet (a fresh add, entries arriving from another Mac) at the top.
    private var displayed: [CorrectionsStore.Correction] {
        let byID = Dictionary(store.corrections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = order.compactMap { byID[$0] }
        let knownIDs = Set(order)
        return newestFirst.filter { !knownIDs.contains($0.id) } + known
    }

    private func refreshOrder() {
        let live = Set(store.corrections.map(\.id))
        let kept = order.filter { live.contains($0) }
        let keptIDs = Set(kept)
        order = newestFirst.map(\.id).filter { !keptIDs.contains($0) } + kept
    }

    /// Newest first. Storage order is not display order: a merge re-sorts the
    /// whole list by `modifiedAt` ascending (`CloudSync.mergeCorrections`), so
    /// inserting locally at the top would survive only until the next sync.
    /// Sorting the view instead holds either way.
    private var newestFirst: [CorrectionsStore.Correction] {
        store.corrections.sorted {
            $0.modifiedAt == $1.modifiedAt
                ? $0.id.uuidString > $1.id.uuidString
                : $0.modifiedAt > $1.modifiedAt
        }
    }

    private var footnote: String {
        if draft != nil {
            return "Type what PUSH hears, then what it should insert. Choose “In context” for words that are also ordinary English, so they are replaced when you mean the name and left alone otherwise."
        }
        let count = store.corrections.count
        return count == 0
            ? "Corrections are applied to every transcription before it is inserted."
            : "\(count) correction\(count == 1 ? "" : "s") · applied to every transcription before it is inserted."
    }

    // MARK: Rows

    @ViewBuilder
    private func draftRow(_ current: Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // prompt:, not the first argument — inside a Form that
                // argument becomes a label beside the field, which both drew
                // the placeholder twice and squeezed the field to ~65pt.
                TextField("", text: Binding(
                    get: { draft?.wrong ?? "" },
                    set: { value in
                        draft?.wrong = value
                        // Default new common-word entries to Context (safer),
                        // unless the mode was already picked by hand.
                        if draft?.modeManuallySet == false {
                            draft?.contextual = WordChecker.isCommonWord(value)
                        }
                    }
                ), prompt: Text("Heard as"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
                .focused($draftFieldFocused)
                .onSubmit(commitDraft)
                // Focus has to wait for the field to exist; setting it in the
                // + action lands before this row is in the hierarchy.
                .onAppear { draftFieldFocused = true }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("", text: Binding(
                    get: { draft?.right ?? "" },
                    set: { draft?.right = $0 }
                ), prompt: Text("Should be"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
                .onSubmit(commitDraft)

                modePicker(
                    isContextual: Binding(
                        get: { draft?.contextual ?? false },
                        set: { draft?.contextual = $0; draft?.modeManuallySet = true }
                    )
                )

                Button("Add", action: commitDraft)
                    .buttonStyle(.borderedProminent)
                    .disabled(!current.isComplete)
                    .help("Add this correction")

                Button {
                    draft = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Discard this row")
            }

            if current.contextual {
                entityField(text: Binding(
                    get: { draft?.entity ?? "" },
                    set: { draft?.entity = $0 }
                ))
            }

            if WordChecker.isCommonWord(current.wrong) && !current.contextual {
                Label("“\(current.wrong)” is also a common word — “In context” avoids over-correcting it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func correctionRow(_ correction: Binding<CorrectionsStore.Correction>) -> some View {
        let entityText = Binding<String>(
            get: { correction.wrappedValue.entity ?? "" },
            set: { correction.entity.wrappedValue = $0.isEmpty ? nil : $0 }
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("", text: correction.wrong)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("", text: correction.right)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)

                modePicker(isContextual: Binding(
                    get: { correction.wrappedValue.kind == .contextual },
                    set: { correction.kind.wrappedValue = $0 ? .contextual : .always }
                ))

                Button {
                    store.remove(correction.wrappedValue)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Remove this correction")
            }

            if correction.wrappedValue.kind == .contextual {
                entityField(text: entityText)
            }
        }
        .padding(.vertical, 2)
    }

    private func modePicker(isContextual: Binding<Bool>) -> some View {
        Picker("", selection: isContextual) {
            Text("Always").tag(false)
            Text("In context").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Always replace, or only when the context fits")
    }

    private func entityField(text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", text: text, prompt: Text("what is it? (e.g. a person named Hamer)"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .font(.caption)
        }
    }

    // MARK: Draft

    /// Turns a complete draft into a real entry. An incomplete one is dropped —
    /// leaving a half-typed row behind would be worse than losing it, since it
    /// cannot be saved anyway.
    private func commitDraft() {
        guard let current = draft else { return }
        if current.isComplete {
            store.addCorrection(
                wrong: current.wrong,
                right: current.right,
                kind: current.contextual ? .contextual : .always,
                entity: current.contextual ? current.entity : nil
            )
        }
        draft = nil
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
#endif

/// Mirrors `AssetInventory.Status` so the view can hold it in `@State` without the
/// whole view needing `@available(macOS 26, *)`.
enum AppleSpeechAssetStatus {
    case unknown
    case installed
    case willInstall
    case installing
    case unsupported
}
