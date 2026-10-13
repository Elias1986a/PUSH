import SwiftUI
import AppKit
import PUSHCore

/// The welcome wizard shown on first launch.
///
/// PUSH is `LSUIElement`: no Dock icon, no launch window, nothing but a menu
/// bar glyph. Without this, a first launch is three unexplained events in a
/// row — a bare microphone prompt, an Accessibility prompt (or, worse, silence
/// while the hotkey does nothing), and an hourglass in the menu bar while a
/// model downloads. Every one of those reads as a broken app to someone who
/// has just paid for it.
///
/// So the wizard exists to put a sentence in front of each of them. It is not
/// a settings pane in disguise: beyond launch at login and the pill, it asks
/// only for what the app cannot start without — two permissions and a speech
/// model, which it downloads here rather than behind the user's back. The
/// small supporting models (voice activity detection) still load on their own
/// at launch; only the ~600 MB speech model waits for this step.
struct OnboardingView: View {

    /// Called when the wizard is finished with — by the last step's button, or
    /// by skipping. The window controller closes itself and records that the
    /// user has seen this.
    let onFinish: () -> Void

    @Environment(AppState.self) private var appState
    @StateObject private var permissions = PermissionsModel()
    @StateObject private var launchAtLogin = LaunchAtLoginModel()

    @State private var step: OnboardingFlow.Step = Self.initialStep
    @State private var typingStepSeen = false
    @State private var typingSandbox = ""
    @FocusState private var typingSandboxFocused: Bool

    /// `PUSH_ONBOARDING_STEP=typingModel` opens the wizard on that step, for
    /// screenshots and testing. Debug builds only. After macOS relaunched
    /// PUSH mid-wizard, the page the user was on.
    private static var initialStep: OnboardingFlow.Step {
        if let resumed = OnboardingWindowController.takeResumeStep() { return resumed }
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["PUSH_ONBOARDING_STEP"],
           let step = OnboardingFlow.Step.allCases.first(where: { "\($0)" == raw }) {
            return step
        }
        #endif
        return .welcome
    }
    /// What the user dictated into the sandbox on step 3. Its contents are
    /// never read, logged, or persisted — only whether it is empty, to show the
    /// "that worked" confirmation.
    @State private var sandboxText = ""
    @FocusState private var sandboxFocused: Bool

    /// Models already on disk. Read from the filesystem on appear and after a
    /// download, never from `body`.
    @State private var modelsOnDisk: Set<WhisperModel> = []
    @State private var downloadingModel: WhisperModel?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?

    /// The steps for the features chosen so far. Recomputed as the switches on
    /// the features step change; `step` is a value, not an index, so it stays
    /// put when the list around it grows or shrinks.
    private var steps: [OnboardingFlow.Step] {
        OnboardingFlow.steps(dictation: appState.dictationEnabled, type: appState.typeEnabled,
                             typingSeen: typingStepSeen)
            // The try-it sandbox is dictation's until Type gets its own (Phase 5).
            .filter { $0 != .tryIt || appState.dictationEnabled }
    }

    var body: some View {
        // `@Observable` has no projected value of its own; `@Bindable`
        // is what gives the controls below their `$appState` bindings.
        @Bindable var appState = appState

        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 36)
                .padding(.top, 34)

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: OnboardingWindowController.contentSize.width,
               height: OnboardingWindowController.contentSize.height)
        .onAppear {
            // A resumed page that no longer applies (its feature switched
            // off meanwhile) would leave Continue with nowhere to go.
            if !steps.contains(step) { step = .welcome }
            permissions.startPolling()
            refreshModelsOnDisk()
            // A first run starts on the recommended model, whatever preference
            // happens to be saved (a dev build's, or one left by an earlier
            // install). Once a model is on disk the user has chosen before,
            // and their choice stands.
            if modelsOnDisk.isEmpty {
                appState.selectedWhisperModel = .defaultModel
            }
        }
        .onDisappear(perform: permissions.stopPolling)
        .task { await launchAtLogin.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .features: featuresStep
        case .permissions: permissionsStep
        case .speechModel: modelStep
        case .typingModel: typingModelStep
        case .screenText: screenTextStep
        case .tryIt: tryItStep
        case .finish: finishStep
        }
    }

    // MARK: - Step 1 · what this is

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            AppIconImage(size: 84)

            VStack(spacing: 8) {
                Text("Meet PUSH")
                    .font(.system(size: 26, weight: .semibold))

                Text("Instant, on-device speech to text.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                highlight(
                    icon: "mic.fill",
                    title: "Hold a key, speak, let go",
                    detail: "Your words land in whatever you were typing in — any app, any text field."
                )
                highlight(
                    icon: "bolt.fill",
                    title: "No waiting for a server",
                    detail: "Transcription runs on this Mac's Neural Engine, in a fraction of a second."
                )
                highlight(
                    icon: "lock.fill",
                    title: "Nothing leaves your Mac",
                    detail: "No account, no upload, no transcript stored anywhere. It works on a plane."
                )
                highlight(
                    icon: "text.alignleft",
                    title: "And a teleprompter",
                    detail: "Read a script off your screen while you record — invisible to the recording itself."
                )
            }
            .padding(.top, 4)
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    private func highlight(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Features · what this Mac runs

    private var featuresStep: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "What should PUSH do?",
                subtitle: "Turn on what you want. Each one can be switched on or off later in Settings."
            )

            featureCard(
                icon: "mic.fill",
                title: "Dictation",
                detail: "Hold a key, speak, and your words are typed into any app. Includes the teleprompter, which follows along as you read a script."
            ) {
                Toggle("Dictation", isOn: $appState.dictationEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            featureCard(
                icon: "text.cursor",
                title: "Type",
                detail: "As you type in any app, PUSH suggests how the sentence goes on. Press Tab to take it a word at a time. Runs on this Mac like everything else."
            ) {
                Toggle("Type", isOn: $appState.typeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if !appState.dictationEnabled && !appState.typeEnabled {
                statusLine(icon: "info.circle", text: "Turn on at least one to continue.", tint: .secondary)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Step 2 · the permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            if OnboardingFlow.needsMicrophone(dictation: appState.dictationEnabled) {
                stepHeader(
                    title: "Two permissions",
                    subtitle: "macOS asks for both. PUSH cannot dictate without them, and it asks for nothing else."
                )
            } else {
                stepHeader(
                    title: "One permission",
                    subtitle: "macOS asks for it. PUSH cannot see what you type without it, and it asks for nothing else."
                )
            }

            if OnboardingFlow.needsMicrophone(dictation: appState.dictationEnabled) {
                OnboardingPermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "So PUSH can hear you. The audio is transcribed on this Mac and thrown away.",
                    status: permissions.microphone,
                    actionTitle: permissions.microphone == .notDetermined
                        ? "Allow Microphone…"
                        : "Open System Settings…",
                    action: {
                        if permissions.microphone == .notDetermined {
                            Task { await permissions.requestMicrophone() }
                        } else {
                            // Already answered once — macOS will not ask again, so
                            // the switch in System Settings is the only way back.
                            permissions.openMicrophoneSettings()
                        }
                    }
                )
            }

            OnboardingPermissionRow(
                icon: "hand.tap.fill",
                title: "Accessibility",
                detail: appState.dictationEnabled
                    ? "So PUSH can see the push-to-talk key and paste into the app you are using."
                    : "So PUSH can read the text around your cursor and type the words you accept.",
                status: permissions.accessibility,
                actionTitle: "Open System Settings…",
                action: {
                    // Opens the list with PUSH on a card beside it to drag in.
                    // No system prompt first: its dialog would sit on top of
                    // the very list the card is pointing at.
                    PermissionGuide.shared.show(.accessibility)
                }
            )

            if !permissions.accessibility.isGranted {
                Label(
                    "System Settings opens with PUSH on a card at the bottom — drag it into the list. This page ticks over on its own once you do — no need to restart PUSH.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Step 3 · a speech model

    /// The one download PUSH cannot run without, chosen and watched here. Launch
    /// no longer fetches a model on its own (`ModelLoader.activateAtLaunch`), so
    /// on a first run this step is where the app becomes able to dictate, and
    /// Continue stays off until it can.
    private var modelStep: some View {
        let chosen = appState.selectedWhisperModel
        return VStack(alignment: .leading, spacing: 14) {
            stepHeader(
                title: "Choose a speech model",
                subtitle: "Everything is transcribed on this Mac, so PUSH needs one model first — about 600 MB, downloaded once."
            )

            VStack(spacing: 8) {
                ForEach(WhisperModel.selectable) { model in
                    modelCard(model, isChosen: model == chosen)
                }
            }

            modelAction(for: chosen)

            Spacer(minLength: 0)
        }
    }

    private func modelCard(_ model: WhisperModel, isChosen: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isChosen ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.shortName).font(.system(size: 13, weight: .medium))
                    if let badge = model.badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    if modelsOnDisk.contains(model) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Downloaded")
                    }
                }
                Text(Self.blurb(for: model))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isChosen ? Color.accentColor : Color.secondary.opacity(0.2),
                              lineWidth: isChosen ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { choose(model) }
        // Switching mid-download would abandon 600 MB half-fetched.
        .disabled(downloadingModel != nil)
        .opacity(downloadingModel != nil && !isChosen ? 0.5 : 1)
    }

    /// One line each. `modelDescription` is written for Settings, where there
    /// is room; four of those would not fit this window.
    private static func blurb(for model: WhisperModel) -> String {
        switch model {
        case .parakeetUltra:
            return "English, plus Spanish, French, German and other European languages."
        case .parakeetStreaming:
            return "English only. Shows your words as you speak them."
        case .nemotronMultilingual:
            return "Chinese, Japanese, Arabic, Hindi, Russian and more. Pick the language in Settings."
        }
    }

    @ViewBuilder
    private func modelAction(for chosen: WhisperModel) -> some View {
        if downloadingModel == chosen {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: downloadProgress)
                Text(downloadProgress < 0.95
                     ? "Downloading \(chosen.shortName)… \(Int(downloadProgress * 100))%"
                     : "Getting \(chosen.shortName) ready…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if isReady(chosen) {
            statusLine(icon: "checkmark.circle.fill", text: "\(chosen.shortName) is ready.", tint: .green)
        } else if modelsOnDisk.contains(chosen) {
            // On disk but not loaded yet: `choose` has started it.
            statusLine(icon: "hourglass", text: "Loading \(chosen.shortName)…", tint: .secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button("Download \(chosen.shortName) · \(chosen.downloadSizeLabel)") { download(chosen) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                if let downloadError {
                    statusLine(icon: "exclamationmark.triangle.fill",
                               text: "The download stopped: \(downloadError) Check your connection and try again.",
                               tint: .orange)
                }
            }
        }
    }

    private func isReady(_ model: WhisperModel) -> Bool {
        modelsOnDisk.contains(model) && appState.activeModel == model && appState.isModelReady
    }

    /// Picking a card records the preference, and brings the model up straight
    /// away when it is already on disk — a reinstall, or a second Mac.
    private func choose(_ model: WhisperModel) {
        guard downloadingModel == nil else { return }
        downloadError = nil
        appState.selectedWhisperModel = model
        if modelsOnDisk.contains(model) {
            Task { try? await ModelLoader.activate(model) }
        }
    }

    private func download(_ model: WhisperModel) {
        appState.selectedWhisperModel = model
        downloadingModel = model
        downloadError = nil
        Task {
            do {
                try await ModelDownload.run(model) { downloadProgress = $0 }
            } catch is CancellationError {
                // Superseded by another activation; nothing to report.
            } catch {
                downloadError = error.localizedDescription
            }
            downloadingModel = nil
            refreshModelsOnDisk()
        }
    }

    private func refreshModelsOnDisk() {
        modelsOnDisk = ModelAvailability.downloaded()
    }

    // MARK: - Type: switch, model, try it

    /// One page decides Type: switch it on, pick and download a model, try it
    /// in the box — and if it is not for you, switch it off right here and
    /// carry on with dictation alone.
    private var typingModelStep: some View {
        @Bindable var appState = appState
        let ready = typingModelOnDisk && appState.typingModelReady
        return VStack(alignment: .leading, spacing: 12) {
            stepHeader(
                title: "Suggestions as you type",
                subtitle: "PUSH suggests how your sentence goes on, in any app, on this Mac. Tab takes the next word."
            )

            HStack {
                Text("Suggest as I type").fontWeight(.medium)
                Spacer()
                Toggle("Suggest as I type", isOn: $appState.typeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            if appState.typeEnabled {
                VStack(spacing: 4) {
                    ForEach(TypingModel.allCases) { model in
                        TypingModelRow(model: model, allowsDelete: false, compact: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

                HStack {
                    Text("Also suggest in code editors")
                    Spacer()
                    Toggle("Also suggest in code editors", isOn: $appState.typingInCodeEditors)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .help("Xcode, VS Code and Cursor use Tab for their own completions, so this starts off.")

                if ready {
                    TextEditor(text: $typingSandbox)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 84)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(alignment: .topLeading) {
                            if typingSandbox.isEmpty {
                                Text("Try it: type “Thanks for the update, I’ll” and wait a moment. Tab takes a word.")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(typingSandboxFocused ? Color.accentColor : Color.secondary.opacity(0.35),
                                          lineWidth: typingSandboxFocused ? 2 : 1))
                        .focused($typingSandboxFocused)
                        .onAppear {
                            TypingCoordinator.shared.allowsOwnWindows = true
                            typingSandboxFocused = true
                        }
                        .onDisappear { TypingCoordinator.shared.allowsOwnWindows = false }
                    Text("Not for you? Switch it off above and continue — PUSH stays a dictation app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    statusLine(
                        icon: TypingModelStore.shared.downloading != nil || typingModelOnDisk ? "hourglass" : "arrow.down.circle",
                        text: TypingModelStore.shared.downloading != nil ? "Downloading — you can try it here as soon as it’s done."
                            : typingModelOnDisk ? "Getting the model ready…"
                            : "Download a model to try it here.",
                        tint: .secondary
                    )
                }
            } else {
                statusLine(icon: "info.circle",
                           text: appState.dictationEnabled
                               ? "Type is off. You can switch it on any time in Settings → Typing."
                               : "Type is off, and so is Dictation. Switch one on to continue.",
                           tint: .secondary)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            typingStepSeen = true
            TypingModelStore.shared.refresh()
        }
    }

    // MARK: - Step 4 · try it here

    /// Optional, Type only: Screen Recording, on a page of its own so there
    /// is room to say what it is for and what it is not (user, 2026-10-12).
    private var screenTextStep: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                title: "Reading the screen",
                subtitle: "Optional. Suggestions are better when PUSH can see what you’re replying to."
            )

            Text("PUSH reads the text around the field you’re typing in — the email you’re answering, the chat above, the page you’re on. Most apps share that text directly. A few only draw it on screen, and for those PUSH needs Screen Recording to read it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingPermissionRow(
                icon: "rectangle.dashed.badge.record",
                title: "Screen Recording",
                detail: "Read only at the moment of a suggestion, on this Mac. Nothing is recorded, kept or sent, and password fields are never read.",
                status: permissions.screenRecording,
                actionTitle: "Allow Screen Recording…",
                action: {
                    OnboardingWindowController.rememberStep(.screenText)
                    permissions.requestScreenRecording()
                }
            )

            HStack {
                Text("Use the text around the field").fontWeight(.medium)
                Spacer()
                Toggle("Use the text around the field", isOn: $appState.typingUsesScreen)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            Label(
                "You can skip this: Type works without it, using what it can read directly. macOS may remind you now and then that PUSH can see your screen. Change either in Settings ▸ Typing.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var tryItStep: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                title: "Try it right here",
                subtitle: "Click the box below, then hold \(appState.selectedHotkey.displayName), say “hello world”, and let go."
            )

            // A real text field, in the app that is frontmost — so the paste
            // path the user is about to rely on every day is exactly the one
            // being exercised here, not a simulation of it.
            TextEditor(text: $sandboxText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            sandboxFocused ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: sandboxFocused ? 2 : 1
                        )
                )
                .focused($sandboxFocused)
                .onAppear { sandboxFocused = true }

            sandboxStatus

            // Once a page of its own; here it follows seeing the pill.
            HStack {
                Text("The pill").fontWeight(.medium)
                Spacer()
                Picker("The pill", selection: $appState.pillPosition) {
                    ForEach(AppState.PillPosition.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            Spacer(minLength: 0)
        }
    }

    /// Live feedback under the sandbox, so the user can tell the difference
    /// between "still loading", "I am hearing you", and "nothing is happening".
    @ViewBuilder
    private var sandboxStatus: some View {
        // A missing permission is checked before anything else, because it is
        // the only thing here that makes the step outright impossible — and the
        // only one the user can do something about. A model still downloading
        // is a wait; no Accessibility is a dead end. Both are true at once on a
        // genuine first run, and reporting the wait instead left someone
        // holding a key that could never fire: exactly the silent failure this
        // wizard exists to prevent.
        //
        // Neither can be true during a live dictation anyway — the hotkey needs
        // Accessibility and capture needs the microphone — so nothing below
        // gets starved by putting them first.
        if !permissions.accessibility.isGranted {
            statusLine(
                icon: "exclamationmark.triangle.fill",
                text: "The push-to-talk key needs Accessibility, which is not granted yet. Go back a step to turn it on — nothing will happen when you hold the key until you do.",
                tint: .orange
            )
        } else if !permissions.microphone.isGranted {
            statusLine(
                icon: "exclamationmark.triangle.fill",
                text: "PUSH cannot hear you without microphone access. Go back a step to turn it on.",
                tint: .orange
            )
        } else if appState.isCapturing {
            statusLine(icon: "waveform", text: "Listening… keep talking, then let go of the key.", tint: .green)
        } else if appState.isListening {
            statusLine(icon: "hourglass", text: "Warming up the microphone…", tint: .orange)
        } else if appState.isProcessing {
            statusLine(icon: "hourglass", text: "Transcribing…", tint: .orange)
        } else if !sandboxText.isEmpty {
            statusLine(icon: "checkmark.circle.fill", text: "That is it. It works the same in every other app.", tint: .green)
        } else if !appState.isModelReady {
            statusLine(icon: "hourglass", text: "Loading the speech model…", tint: .secondary)
        } else {
            statusLine(
                icon: "keyboard",
                text: "Hold \(appState.selectedHotkey.displayName) and speak. Press ⎋ Esc to cancel a recording.",
                tint: .secondary
            )
        }
    }

    private func statusLine(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .foregroundStyle(tint == .secondary ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    // MARK: - Pieces

    /// One feature: icon, name, what it is, and whatever control or aside it
    /// needs underneath.
    private func featureCard<Extra: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Last page · keep it around

    private var finishStep: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "One last thing",
                subtitle: "PUSH lives in the menu bar. It has no Dock icon and no window of its own."
            )

            Toggle(isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.set($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open PUSH at login").font(.system(size: 13, weight: .medium))
                    Text("Recommended. Dictation is only useful if it is already running when you want it — otherwise the hotkey does nothing and you have to go and launch PUSH first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Where to find things")
                    .font(.system(size: 13, weight: .medium))

                bullet("Click the ", symbol: "music.mic", rest: " in the menu bar for settings, the teleprompter, and to quit.")
                bullet("Change the push-to-talk key, the dictation language and the pill's position in Settings.")
                bullet("Teach PUSH names and jargon it keeps mishearing under Settings → Dictionary.")
            }

            if appState.dictationEnabled {
                Divider()

                // Once a page of their own ("Two more things"); both are off by
                // default, so a line each is enough here.
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $appState.wakeWordEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Start recording when I say “\(appState.wakeWord)”").font(.system(size: 13, weight: .medium))
                            Text("Off by default: it keeps the microphone open the whole time, where push-to-talk opens it only while you hold the key.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: appState.wakeWordEnabled) { _, on in
                        if on { WakeWordListener.shared.startListening() } else { WakeWordListener.shared.stopListening() }
                    }
                    bullet("Teleprompter: paste a script and read it off the top of your screen; PUSH follows your voice. Start it from the menu bar.")
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func bullet(_ text: String, symbol: String? = nil, rest: String = "") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Text(text)
                if let symbol {
                    Image(systemName: symbol)
                    Text(rest)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step == .welcome {
                // No way round a model step until that feature has a model on
                // disk: the app cannot run it without one, and launch will not
                // fetch it.
                if canSkip {
                    Button("Skip", action: onFinish)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Back") { advance(to: -1) }
            }

            Spacer()

            stepDots

            Spacer()

            if step == .finish {
                Button("Start Using PUSH", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { advance(to: 1) }
                    .keyboardShortcut(.defaultAction)
                    // Never disabled for permissions: a wizard that traps
                    // someone on a step they cannot satisfy — a managed Mac
                    // where an admin owns these switches, say — is worse than
                    // one they can walk out of, and Settings shows the same two
                    // rows afterwards. The model is different: it is a download
                    // the user can always start, and there is no app without it.
                    .disabled(continueDisabled)
            }
        }
    }

    /// Skip is offered only when every feature that is on can already run.
    private var canSkip: Bool {
        (appState.dictationEnabled || appState.typeEnabled)
            && (!appState.dictationEnabled || !modelsOnDisk.isEmpty)
            && (!appState.typeEnabled || typingModelOnDisk)
    }

    private var typingModelOnDisk: Bool {
        TypingModelStore.shared.onDisk.contains(appState.selectedTypingModel)
    }

    private var continueDisabled: Bool {
        switch step {
        case .features: return !appState.dictationEnabled && !appState.typeEnabled
        case .speechModel: return !isReady(appState.selectedWhisperModel)
        // A download in progress carries on in the background.
        case .typingModel:
            return appState.typeEnabled ? !typingModelOnDisk && TypingModelStore.shared.downloading == nil
                : !appState.dictationEnabled
        default: return false
        }
    }

    private var stepDots: some View {
        let steps = steps
        let index = steps.firstIndex(of: step) ?? 0
        return HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Step \(index + 1) of \(steps.count)")
    }

    private func advance(to offset: Int) {
        let steps = steps
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + offset) else { return }
        withAnimation(.easeInOut(duration: 0.16)) { step = steps[index + offset] }
    }
}

/// One permission, with a checkmark that ticks over on its own while the user
/// is in System Settings — `PermissionsModel` polls for exactly this.
private struct OnboardingPermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: PermissionsModel.Status
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(status.isGranted ? Color.green : Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if status.isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .transition(.opacity)
            } else {
                Button(actionTitle, action: action)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: status.isGranted)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    status.isGranted ? Color.green.opacity(0.5) : Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
}

#if DEBUG
#Preview("Onboarding") {
    OnboardingView(onFinish: {})
        .environment(AppState.shared)
}
#endif
