import SwiftUI
import AppKit
import PUSHCore
import Combine

// MARK: - General

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
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
        // `@Observable` has no projected value of its own; `@Bindable`
        // is what gives the controls below their `$appState` bindings.
        @Bindable var appState = appState

        Form {
            Section {
                HStack(spacing: 15) {
                    // NSApp's own icon, not a bundled asset: Bundle.module
                    // resource lookup crashes in distribution builds.
                    // See AppIconImage for the unbundled-build stand-in.
                    AppIconImage(size: 56)

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
