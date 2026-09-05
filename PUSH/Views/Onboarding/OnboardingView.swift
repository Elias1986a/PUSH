import SwiftUI
import AppKit
import PUSHCore

/// The four-step welcome wizard shown on first launch.
///
/// PUSH is `LSUIElement`: no Dock icon, no launch window, nothing but a menu
/// bar glyph. Without this, a first launch is three unexplained events in a
/// row — a bare microphone prompt, an Accessibility prompt (or, worse, silence
/// while the hotkey does nothing), and an hourglass in the menu bar while a
/// model downloads. Every one of those reads as a broken app to someone who
/// has just paid for it.
///
/// So the wizard exists to put a sentence in front of each of them. It is not
/// a settings pane in disguise: the only preference it touches is launch at
/// login, and everything else is either an explanation or a permission the app
/// cannot start without.
struct OnboardingView: View {

    /// Called when the wizard is finished with — by the last step's button, or
    /// by skipping. The window controller closes itself and records that the
    /// user has seen this.
    let onFinish: () -> Void

    @Environment(AppState.self) private var appState
    @StateObject private var permissions = PermissionsModel()
    @StateObject private var launchAtLogin = LaunchAtLoginModel()

    @State private var step: Step = .welcome
    /// What the user dictated into the sandbox on step 3. Its contents are
    /// never read, logged, or persisted — only whether it is empty, to show the
    /// "that worked" confirmation.
    @State private var sandboxText = ""
    @FocusState private var sandboxFocused: Bool

    enum Step: Int, CaseIterable {
        case welcome, permissions, tryIt, pill, more, finish
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
        .onAppear(perform: permissions.startPolling)
        .onDisappear(perform: permissions.stopPolling)
        .task { await launchAtLogin.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .permissions: permissionsStep
        case .tryIt: tryItStep
        case .pill: pillStep
        case .more: moreStep
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

    // MARK: - Step 2 · the two permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                title: "Two permissions",
                subtitle: "macOS asks for both. PUSH cannot dictate without them, and it asks for nothing else."
            )

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

            OnboardingPermissionRow(
                icon: "hand.tap.fill",
                title: "Accessibility",
                detail: "So PUSH can see the push-to-talk key and paste into the app you are using.",
                status: permissions.accessibility,
                actionTitle: "Open System Settings…",
                action: {
                    permissions.requestAccessibility()
                    permissions.openAccessibilitySettings()
                }
            )

            if !permissions.accessibility.isGranted {
                Label(
                    "In System Settings, switch PUSH on under Privacy & Security → Accessibility. This page ticks over on its own once you do — no need to restart PUSH.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Step 3 · try it here

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 18) {
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
            statusLine(
                icon: "arrow.down.circle",
                text: "Getting the speech model ready — this is a one-time download. You can carry on and come back to this.",
                tint: .secondary
            )
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

    // MARK: - Step 4 · where the pill lives

    /// Asked with the same picture Settings uses, so the two read as one
    /// setting rather than two. The choice is genuinely a matter of taste and
    /// of hardware — a notch to hang from, or not — which makes it worth a
    /// step rather than a line of prose nobody reads.
    private var pillStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                title: "Where the pill lives",
                subtitle: "While you dictate, a small pill shows that PUSH is listening — and a live waveform of your voice."
            )

            HStack(spacing: 18) {
                ForEach(AppState.PillPosition.allCases) { position in
                    PillPositionThumbnail(
                        position: position,
                        isSelected: appState.pillPosition == position
                    )
                    .onTapGesture { appState.pillPosition = position }
                }
                Spacer(minLength: 0)
            }

            Text("At the bottom it floats as a capsule, out of the way. At the top it hangs off the screen edge under the notch, where you are already reading. You can change this any time in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Step 5 · the rest of the app

    private var moreStep: some View {
        // This step is not `body`, so it needs its own `@Bindable` shadow for
        // the wake word toggle's binding.
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Two more things it does",
                subtitle: "Neither is on by default. Both are in Settings whenever you want them."
            )

            // Wake word ships off and must stay off by default: it holds the
            // microphone open continuously, which is a materially different
            // privacy posture from push-to-talk and deserves saying out loud.
            featureCard(
                icon: "waveform.badge.mic",
                title: "Wake word",
                detail: "Say a word instead of holding a key, and PUSH starts recording — stopping on its own after a second of silence."
            ) {
                Toggle("Start recording when I say “\(appState.wakeWord)”", isOn: $appState.wakeWordEnabled)
                    .onChange(of: appState.wakeWordEnabled) { _, on in
                        if on {
                            WakeWordListener.shared.startListening()
                        } else {
                            WakeWordListener.shared.stopListening()
                        }
                    }
                Text("Off by default on purpose: listening for a wake word holds the microphone open the whole time, where push-to-talk only opens it while you hold the key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            featureCard(
                icon: "text.alignleft",
                title: "Teleprompter",
                detail: "Paste a script and read it off the top of your screen. PUSH listens as you read and moves the text to keep up with you — it holds still if you pause or go off-script, and never scrolls on its own."
            ) {
                Label(
                    "It is excluded from screen capture, so it never appears in your recording or on a shared screen. You are reading; nobody else can tell.",
                    systemImage: "eye.slash.fill"
                )
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

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

    // MARK: - Step 6 · keep it around

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                bullet("Start a prompter take from the menu bar; its script and type size live in Settings → Teleprompter.")
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
                Button("Skip", action: onFinish)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
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
                    // Deliberately never disabled, not even with permissions
                    // missing. A wizard that traps someone on a step they
                    // cannot satisfy — a managed Mac where an admin owns these
                    // switches, say — is worse than one they can walk out of;
                    // Settings shows the same two rows afterwards.
            }
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { dot in
                Circle()
                    .fill(dot == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private func advance(to offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        withAnimation(.easeInOut(duration: 0.16)) { step = next }
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
