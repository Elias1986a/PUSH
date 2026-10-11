import SwiftUI
import AppKit
import PUSHCore

/// Settings → Typing: the autocomplete switch, its model, how suggestions
/// behave and look, and where they never appear.
struct TypingSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var customColor = Color.blue
    @State private var inlinePredictionsOn = TypingSettingsView.macInlinePredictionsOn()

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section {
                Toggle(isOn: $appState.typeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggest as I type")
                        Text("Suggestions appear ahead of your cursor in any app. Everything runs on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if appState.typeEnabled { TypingPauseControl() }
            }

            Section("Model") {
                ForEach(TypingModel.allCases) { TypingModelRow(model: $0) }
            }

            Section("Suggestions") {
                Picker("Length", selection: $appState.typingLength) {
                    ForEach(LengthPreset.offered(for: appState.selectedTypingModel), id: \.self) { preset in
                        Text("\(preset.rawValue.capitalized) · \(preset.label)").tag(preset)
                    }
                }
                LabeledContent("Accept") {
                    Text("\(Text("Tab").bold()) next word · \(Text(Self.wholeKeyName).bold()) the whole suggestion")
                        .foregroundStyle(.secondary)
                }
                Toggle("Add a space after the last word", isOn: $appState.typingSpaceAfterLastWord)
                Toggle(isOn: $appState.typingInCodeEditors) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggest in code editors")
                        Text("Off by default: Xcode, VS Code and Cursor use Tab for their own completions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Appearance") {
                HStack(spacing: 10) {
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
                Text("Always off in password managers, Keychain Access and System Settings, and in password and sign-in fields everywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Battery") {
                Toggle("Pause on battery and in Low Power Mode", isOn: $appState.typingPauseOnBattery)
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
        }
    }

    private func swatch(_ color: Color, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// The key that accepts the whole suggestion in this keyboard layout.
    static var wholeKeyName: String {
        AcceptKeyResolver.wholeSuggestionKey(layout: KeyboardLayoutMap.current()).isFallback ? "⌥Tab" : "` (above Tab)"
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
