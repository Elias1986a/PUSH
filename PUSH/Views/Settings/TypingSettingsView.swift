import SwiftUI
import AppKit
import PUSHCore

/// Settings → Typing: the autocomplete switch, its model, how suggestions
/// behave and look, and where they never appear.
struct TypingSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var customColor = Color.gray
    @State private var inlinePredictionsOn = TypingSettingsView.macInlinePredictionsOn()
    @State private var screenRecordingAllowed = ScreenOCR.isAllowed
    /// Bumped when an accept key changes; the keys live in UserDefaults.
    @State private var keysVersion = 0

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section {
                Toggle(isOn: $appState.typeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TYPE")
                        Text("Suggestions appear ahead of your cursor in any app. Everything runs on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if appState.typeEnabled { TypingPauseControl() }
            }

            Section("Suggestions") {
                Picker("Length", selection: $appState.typingLength) {
                    ForEach(LengthPreset.offered(for: appState.selectedTypingModel), id: \.self) { preset in
                        Text("\(preset.rawValue.capitalized) · \(preset.label)").tag(preset)
                    }
                }
                acceptKeys
                Toggle("Add a space after the last word", isOn: $appState.typingSpaceAfterLastWord)
                Toggle(isOn: $appState.typingFixTypos) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offer spelling fixes")
                        Text("When a word is misspelled, the gray text shows the correction. Your accept key swaps it in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $appState.typingInCodeEditors) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggest in code editors")
                        Text("Off by default: Xcode, VS Code, and Cursor use Tab for their own completions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Pause on battery and in Low Power Mode", isOn: $appState.typingPauseOnBattery)
            }

            Section {
                Toggle(isOn: $appState.typingUsesClipboard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use what I just copied")
                        Text("Something you copied in the last few minutes can shape the suggestion — an address, a name, a line to reply to.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $appState.typingUsesScreen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use the text around the field")
                        Text("The message you’re replying to, the chat above, the page you’re on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if appState.typingUsesScreen {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apps that hide their text")
                            Text("A few apps draw text PUSHTYPE can’t read directly. With Screen Recording allowed, it reads those from the screen instead.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if screenRecordingAllowed {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Allow…") {
                                // Asks once; after that only System Settings can change it.
                                if !CGRequestScreenCaptureAccess() {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Context")
            } footer: {
                Text("Read only at the moment of a suggestion, on this Mac. Never kept, never sent. Passwords and anything a password manager copies are never read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Appearance") {
                HStack(spacing: 8) {
                    ForEach(SuggestionColor.Preset.allCases) { preset in
                        swatch(Color(nsColor: preset.color), selected: appState.typingColor == .preset(preset),
                               help: preset.name) { appState.typingColor = .preset(preset) }
                    }
                    ColorPicker("Custom", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom color")
                        .onChange(of: customColor) { _, color in
                            appState.typingColor = SuggestionColor(custom: NSColor(color))
                        }
                }
                Toggle("Show an icon beside the field you’re typing in", isOn: $appState.typingShowIndicator)
                (Text("Can we ") + Text("meet at the hotel?").foregroundColor(Color(nsColor: appState.typingColor.color)))
                    .font(.system(size: 15))
                    .padding(.vertical, 2)
            }

            Section {
                ForEach(appState.typingExcludedApps, id: \.self) { id in
                    HStack {
                        AppLabel(bundleID: id)
                        Spacer()
                        Button {
                            appState.typingExcludedApps.removeAll { $0 == id }
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .help("Suggest in this app again")
                        .accessibilityLabel("Suggest in this app again")
                    }
                }
                Menu("Turn Off in an App…") {
                    ForEach(Self.runningApps(excluding: appState.typingExcludedApps), id: \.bundleID) { app in
                        Button(app.name) { appState.typingExcludedApps.append(app.bundleID) }
                    }
                    Divider()
                    Button("Choose an App…") { chooseApp() }
                }
                .fixedSize()
            } header: {
                Text("Apps")
            } footer: {
                Text("Always off in password managers, Keychain Access, and System Settings, and in password and sign-in fields everywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if inlinePredictionsOn {
                Section("macOS predictions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("macOS shows its own gray predictions, which also take Tab. Turning them off avoids two suggestions at once: Keyboard → Text Input → Edit → “Show inline predictive text”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Keyboard Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            TypingModelStore.shared.refresh()
            if case .custom = appState.typingColor { customColor = Color(nsColor: appState.typingColor.color) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inlinePredictionsOn = Self.macInlinePredictionsOn()
            screenRecordingAllowed = ScreenOCR.isAllowed
        }
    }

    private func swatch(_ color: Color, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// The two accept keys, chosen by the user, and how Tab behaves where
    /// it means something else (explained, not changeable).
    @ViewBuilder
    private var acceptKeys: some View {
        let _ = keysVersion     // re-read after a change
        let layout = KeyboardLayoutMap.current()
        let next = TypingPreferences.nextWordKey()
        let whole = TypingPreferences.wholeKey(layout: layout)
        keyPicker("Next word", defaultsKey: TypingPreferences.nextWordKeyKey,
                  current: next, other: whole, otherName: "Whole suggestion", layout: layout)
        keyPicker("Whole suggestion", defaultsKey: TypingPreferences.wholeKeyKey,
                  current: whole, other: next, otherName: "Next word", layout: layout)
        LabeledContent("In Terminal and other terminals") {
            Text(next == AcceptKeyResolver.tab
                 ? "→ takes the next word. Tab stays the terminal’s, for completing commands."
                 : "Your keys work there too.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        LabeledContent("Moving between form fields") {
            Text("⌥Tab moves to the next field while a suggestion shows.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        if UserDefaults.standard.string(forKey: TypingPreferences.nextWordKeyKey) != nil
            || UserDefaults.standard.string(forKey: TypingPreferences.wholeKeyKey) != nil {
            HStack {
                Spacer()
                Button("Restore Default Keys") {
                    UserDefaults.standard.removeObject(forKey: TypingPreferences.nextWordKeyKey)
                    UserDefaults.standard.removeObject(forKey: TypingPreferences.wholeKeyKey)
                    keysVersion += 1
                }
            }
        }
    }

    /// One accept key: a short menu of single keys, the other one's key
    /// greyed out. (A key recorder offered every key; most were wrong ones.)
    private func keyPicker(_ title: String, defaultsKey: String, current: AcceptKeyResolver.Key,
                           other: AcceptKeyResolver.Key, otherName: String,
                           layout: [Int64: String]) -> some View {
        Picker(title, selection: Binding(
            get: { current.stored },
            set: { stored in
                UserDefaults.standard.set(stored, forKey: defaultsKey)
                keysVersion += 1
            })) {
            ForEach(AcceptKeyResolver.choices(layout: layout), id: \.stored) { key in
                Text(Self.keyLabel(key, layout: layout) + (key == other ? " (Used by \(otherName))" : ""))
                    .tag(key.stored)
                    .disabled(key == other)
            }
        }
    }

    private static func keyLabel(_ key: AcceptKeyResolver.Key, layout: [Int64: String]) -> String {
        switch key.keyCode {
        case 48: return "Tab"
        case 124: return "Right Arrow"
        case 119: return "End"
        default: return AcceptKeyResolver.name(of: key, layout: layout)
        }
    }

    /// macOS 14+ shows inline predictions unless the user turned them off.
    static func macInlinePredictionsOn() -> Bool {
        UserDefaults.standard.object(forKey: "NSAutomaticInlinePredictionEnabled") as? Bool ?? true
    }

    struct RunningApp { let bundleID: String; let name: String }

    static func runningApps(excluding excluded: [String]) -> [RunningApp] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own,
                  !excluded.contains(id), !TypingExclusions.isExcluded(bundleID: id) else { return nil }
            return RunningApp(bundleID: id, name: app.localizedName ?? id)
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Turn Off"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier, !appState.typingExcludedApps.contains(id) else { return }
        appState.typingExcludedApps.append(id)
    }
}

/// An app's icon and name from its bundle id.
struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(url.flatMap { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
                 ?? bundleID)
        }
    }
}
