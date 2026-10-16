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
    @State private var copied: CloudSync.Adoption?

    /// The website's pages.
    static let acknowledgementsURL = URL(string: "https://pushtype.app/legal/notices.html")!
    static let privacyURL = URL(string: "https://pushtype.app/legal/privacy.html")!
    static let licenseAgreementURL = URL(string: "https://pushtype.app/legal/eula.html")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        // `@Observable` has no projected value of its own; `@Bindable`
        // is what gives the controls below their `$appState` bindings.
        @Bindable var appState = appState

        Form {
            Section {
                HStack(spacing: 12) {
                    // NSApp's own icon, not a bundled asset: Bundle.module
                    // resource lookup crashes in distribution builds.
                    // See AppIconImage for the unbundled-build stand-in.
                    AppIconImage(size: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PUSHTYPE")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Dictation and autocomplete, on your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // The open-source licences PUSH ships under ask for
                        // credit where users can find it; the full texts are
                        // also in the app bundle (Contents/Resources/Legal).
                        HStack(spacing: 10) {
                            // Short names, never broken mid-word: three links share
                            // the row with Check for Updates.
                            Link("License Agreement", destination: Self.licenseAgreementURL).fixedSize()
                            Link("Privacy", destination: Self.privacyURL).fixedSize()
                            Link("Acknowledgments", destination: Self.acknowledgementsURL).fixedSize()
                        }
                        .font(.caption)
                        .padding(.top, 2)
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
                Toggle("Open PUSHTYPE at login", isOn: Binding(
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
                Toggle("Sync across my Macs", isOn: $appState.iCloudSyncEnabled)

                Text("Uses the iCloud account this Mac is signed into — no separate login. Dictionary entries are merged, never replaced, and your name and About you follow you. What TYPE has learned travels only if you switch on Share in Settings ▸ Personal. Everything else is copied once, when you ask, and then each Mac keeps its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Copy Settings from My Other Macs") { copied = CloudSync.shared.adoptFromOtherMac() }
                    if let copied {
                        Text(copied.foundAnything ? "Copied \(copied.settings) settings." : "Nothing found in iCloud yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!appState.iCloudSyncEnabled)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    reason: "PUSHTYPE cannot hear you without it.",
                    status: permissions.microphone,
                    openSettings: permissions.openSystemSettings
                )
                PermissionRow(
                    title: "Accessibility",
                    reason: "Needed for the PUSH-to-talk key and for pasting text.",
                    status: permissions.accessibility,
                    openSettings: { PermissionGuide.shared.show(.accessibility) }
                )
                // Optional, and only for TYPE: shown here too so every
                // permission PUSHTYPE can ask for is in one list.
                PermissionRow(
                    title: "Screen Recording (optional)",
                    reason: "Lets TYPE read the few apps that hide their text. Settings ▸ TYPE ▸ Context.",
                    status: ScreenOCR.isAllowed ? .granted : .denied,
                    openSettings: {
                        if !CGRequestScreenCaptureAccess() {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                )
            }

            // For support: the user can send it when something goes wrong. It
            // holds operational events and timings, never text or app names.
            Section {
                HStack {
                    Text("Diagnostic log")
                    Spacer()
                    Button("Show in Finder") {
                        if let url = PushLogger.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Button("Clear") { PushLogger.clear() }
                }
            } header: {
                Text("Troubleshooting")
            } footer: {
                Text("Records what PUSHTYPE does and how long it takes, never what you say or type. It stays on this Mac unless you send it to us.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
