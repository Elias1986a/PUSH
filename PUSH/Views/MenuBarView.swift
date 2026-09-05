import SwiftUI
import AppKit
import PUSHCore

/// The menu bar dropdown.
///
/// A `.window` popover rather than an `NSMenu`. The content here — a status
/// line, a live level meter, a model picker, toggles — is not menu-shaped, and
/// rendering custom SwiftUI inside an `NSMenu` got it adapted awkwardly and
/// stripped of the things that make a real menu good (keyboard navigation,
/// type-select). A popover is honest about what this is: a small control
/// panel. The three genuinely menu-shaped commands keep their standard
/// shortcuts at the bottom.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var updater = UpdaterManager.shared
    @ObservedObject private var session = TeleprompterSession.shared
    @ObservedObject private var audioLevel = AudioLevelMonitor.shared

    /// Models already on disk. Only these are offered: switching should be
    /// instant, and a picker that could start a 600MB download from a menu
    /// click is not something a menu should be able to do.
    @State private var downloaded: Set<AppState.WhisperModel> = []

    /// Languages the *active* engine offers. Resolved asynchronously — Apple
    /// Speech queries the OS and Nemotron reads its prompt dictionary — and
    /// re-resolved when the model changes, because each engine reports a
    /// different set. nil means "not asked yet", which is not the same as an
    /// engine that offers none.
    @State private var languages: [DictationLanguage]?

    /// True when the engine offers languages this menu is not showing, because
    /// they live in a vocabulary build that is not on disk.
    @State private var hasUndownloadedLanguages = false

    var body: some View {
        // `@Observable` has no projected value of its own; `@Bindable`
        // is what gives the controls below their `$appState` bindings.
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            hotkeyRow
            Divider()
            controls
            Divider()
            commands
        }
        .frame(width: 290)
        .onAppear { downloaded = ModelAvailability.downloaded() }
        .task(id: appState.activeModel) { await resolveLanguages() }
    }

    // MARK: - Status

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                Text(appState.activeModel.shortName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // The same level the pill draws, so the popover can stand in for it
            // while you are setting things up with the menu open.
            if appState.isCapturing {
                MenuLevelMeter(level: audioLevel.level)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var hotkeyRow: some View {
        HStack(spacing: 5) {
            Text("Hold")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(appState.selectedHotkey.displayName)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            Text("to speak")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Quick controls

    private var controls: some View {
        // Not `body`, so this needs its own `@Bindable` shadow for the pill and
        // wake word bindings below.
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 9) {
            labelled("Model") {
                Picker("", selection: modelBinding) {
                    ForEach(offeredModels) { model in
                        Text(model.shortName).tag(model)
                    }
                }
                .labelsHidden()
                .disabled(offeredModels.count < 2)
            }

            // Only the multilingual engines have anything to ask. On Parakeet
            // this row would be a permanently disabled control explaining that
            // English is the only option, which is worse than no row.
            if appState.activeModel.supportsLanguageSelection {
                labelled("Language") {
                    Picker("", selection: languageBinding) {
                        ForEach(offeredLanguages) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .disabled(offeredLanguages.count < 2)
                }

                if hasUndownloadedLanguages {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 62, height: 0)
                        Text("More languages in Settings — they need a download.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }

            labelled("Pill") {
                Picker("", selection: $appState.pillPosition) {
                    ForEach(AppState.PillPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // Full width with the switch trailing, and no caption in the
            // gutter: "Wake" beside "Wake word" said the same thing twice.
            // The word itself is the point — a toggle for a word you cannot
            // see is one you have to open Settings to remember.
            HStack(spacing: 8) {
                Text(wakeWordLabel)
                Spacer(minLength: 0)
                Toggle("", isOn: $appState.wakeWordEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: appState.wakeWordEnabled) { _, on in
                        if on {
                            WakeWordListener.shared.startListening()
                        } else {
                            WakeWordListener.shared.stopListening()
                        }
                    }
            }
            .padding(.top, 1)
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// A caption in a fixed gutter with its control filling the rest, so every
    /// picker starts and ends at the same x. A `Form` would do this, but a
    /// grouped Form inside a popover draws its own inset card background and
    /// defeats the material behind it.
    private func labelled<Content: View>(
        _ caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            content()
                .frame(maxWidth: .infinity)
        }
    }

    /// Downloaded models, plus whatever is currently active — a model whose
    /// files were deleted underneath us still has to be representable, or the
    /// Picker has no match for its own selection and blanks itself.
    private var offeredModels: [AppState.WhisperModel] {
        AppState.WhisperModel.selectable.filter {
            downloaded.contains($0) || $0 == appState.activeModel
        }
    }

    private var wakeWordLabel: String {
        let word = appState.wakeWord.trimmingCharacters(in: .whitespaces)
        return word.isEmpty ? "Wake word" : "Wake word (“\(word)”)"
    }

    /// The active engine's languages, always including the current choice —
    /// a saved language the engine no longer reports must still be
    /// representable, or the Picker blanks itself.
    private var offeredLanguages: [DictationLanguage] {
        let current = appState.language(for: appState.activeModel)
        guard let languages, !languages.isEmpty else { return [current] }
        return languages.contains(current) ? languages : (languages + [current]).sorted()
    }

    /// Writes through `AppState.setLanguage` and reloads the engine when the
    /// change affects the model actually serving — the same path the settings
    /// picker uses, because a language chosen here has to take effect on the
    /// running engine rather than only on the next launch.
    private var languageBinding: Binding<DictationLanguage> {
        Binding(
            get: { appState.language(for: appState.activeModel) },
            set: { language in
                let model = appState.activeModel
                guard language != appState.language(for: model) else { return }
                appState.setLanguage(language, for: model)
                // Left to run. A menu click must never wait on a model load:
                // blocking the main thread is how this app loses its event tap.
                Task { try? await ModelLoader.reloadForLanguageChange(model) }
            }
        )
    }

    /// Only languages that are ready to use right now.
    ///
    /// Nemotron ships two ~600MB vocabulary builds, and picking a language from
    /// the other one starts that download. Settings is the place to do that —
    /// it has the room to say what is about to happen and to show progress. A
    /// menu should not be able to start a 600MB download from one click, for
    /// the same reason the model picker above only offers what is on disk.
    private func resolveLanguages() async {
        switch appState.activeModel.engineType {
        case .nemotronMultilingual:
            let all = await NemotronMultilingualEngine.shared.supportedLanguages()
            let resident = all.filter { NemotronMultilingualEngine.isModelDownloaded(for: $0.code) }
            languages = resident
            hasUndownloadedLanguages = resident.count < all.count
        case .appleSpeech:
            // The OS owns these assets and installs them on demand; there is no
            // download of ours to protect the user from.
            if #available(macOS 26, *) {
                languages = await AppleSpeechEngine.supportedLanguages()
            } else {
                languages = []
            }
            hasUndownloadedLanguages = false
        case .parakeet, .parakeetUnified, .parakeetStreaming:
            languages = []
            hasUndownloadedLanguages = false
        }
    }

    /// Reads the *active* model and writes through `ModelLoader`, which owns
    /// activation. Assigning `selectedWhisperModel` directly would move the
    /// preference without loading anything.
    private var modelBinding: Binding<AppState.WhisperModel> {
        Binding(
            get: { appState.activeModel },
            set: { model in
                guard model != appState.activeModel else { return }
                appState.selectedWhisperModel = model
                Task { try? await ModelLoader.activate(model) }
            }
        )
    }

    // MARK: - Commands

    private var commands: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommandRow(
                title: session.isRunning ? "Stop Teleprompter" : "Teleprompter",
                symbol: "text.alignleft",
                action: { run { Task { await Teleprompter.toggle() } } }
            )
            CommandRow(title: "Welcome to PUSH…", symbol: "sparkles") {
                run { OnboardingWindowController.shared.show() }
            }

            Divider().padding(.vertical, 4)

            // Not `SettingsLink`: that only works inside the SwiftUI scene
            // graph, and this view is now hosted in an AppKit popover. The
            // action is the one AppKit itself sends, renamed in macOS 14 with
            // the older selector kept as a fallback.
            CommandRow(title: "Settings…", symbol: "gear", shortcut: "⌘,") {
                run { Self.openSettings() }
            }

            CommandRow(
                title: updater.isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…",
                symbol: "arrow.down.circle",
                action: { run { updater.checkForUpdates() } }
            )
            .disabled(!updater.canBeInvoked)

            Divider().padding(.vertical, 4)

            CommandRow(title: "Quit PUSH", symbol: "power", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    /// Close the panel, then act.
    ///
    /// Every command here either opens a window or ends the app, and a popover
    /// left hanging over the window it just summoned is the giveaway that it is
    /// not a real menu. Dismissing first also hands focus to whatever opens.
    private func run(_ action: @escaping () -> Void) {
        MenuBarController.shared.dismiss()
        // Next runloop, not inline. `performClose` tears the popover's window
        // down and hands focus back as it goes, and an action sent during that
        // finds a responder chain still rooted in the window that is closing —
        // which is why Settings silently did nothing. By the next turn the
        // popover is gone and NSApp is the responder again.
        DispatchQueue.main.async { action() }
    }

    private static func openSettings() {
        SettingsWindowController.shared.show()
    }

    // MARK: - Derived

    private var statusColor: Color {
        if appState.modelUnavailable { return .red }
        if appState.isProcessing { return .orange }
        if appState.isCapturing { return .green }
        if !appState.isModelReady || appState.isPrewarming { return .orange }
        return .secondary
    }

    private var statusText: String {
        if appState.modelUnavailable { return "Model unavailable" }
        if appState.isCapturing { return "Listening" }
        if appState.isListening { return "Warming up…" }
        if appState.isProcessing { return "Transcribing…" }
        if !appState.isModelReady { return "Loading model…" }
        if appState.isPrewarming || appState.isWarmingUp { return "Warming up…" }
        return "Ready"
    }
}

/// A hoverable command line. `Button` with `.plain` inside a popover draws no
/// affordance at all, so the row supplies its own highlight — the thing an
/// NSMenu gave for free and the main reason custom content fought the menu.
private struct CommandRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void

    init(title: String, symbol: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.action = action
    }

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    /// Only a live row highlights. A disabled one that lit up on hover would
    /// promise a click that does nothing.
    private var isHighlighted: Bool { isHovering && isEnabled }

    var body: some View {
        Button(action: action) {
            Label(
                title: title,
                symbol: symbol,
                shortcut: shortcut,
                isHighlighted: isHighlighted
            )
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 5)
                // A solid accent fill, the way AppKit highlights a menu item.
                // At 15% opacity it was almost invisible against the vibrancy
                // behind it — the material is already a mid grey, so a wash
                // that light has nowhere to read against.
                .fill(isHighlighted ? Color.accentColor : .clear)
        )
        .onHover { isHovering = $0 }
    }

    /// The row's contents, shared with `SettingsLink`, which needs a label
    /// rather than an action of its own.
    struct Label: View {
        let title: String
        let symbol: String
        var shortcut: String?
        var isHighlighted = false

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 15)
                    .foregroundStyle(isHighlighted ? Color.white : .secondary)
                Text(title)
                    .foregroundStyle(isHighlighted ? Color.white : .primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        // White at 70% rather than `.tertiary`: hierarchical
                        // styles resolve against the *background* they think
                        // they are on, and on a filled accent row that leaves
                        // the shortcut nearly invisible.
                        .foregroundStyle(isHighlighted ? Color.white.opacity(0.7) : Color.secondary.opacity(0.75))
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
    }
}

/// A compact copy of the pill's waveform, for the popover header.
private struct MenuLevelMeter: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 2.5, height: height(index))
            }
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.09), value: level)
    }

    /// Bars fan out from the middle, so a single published level still reads as
    /// a meter rather than five identical sticks.
    private func height(_ index: Int) -> CGFloat {
        let weight = [0.45, 0.75, 1.0, 0.75, 0.45][index]
        return 2.5 + 9.5 * CGFloat(min(max(level, 0), 1) * weight)
    }
}

#if DEBUG
#Preview {
    MenuBarView()
        .environment(AppState.shared)
}
#endif
