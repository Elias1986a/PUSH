import Foundation
import AVFoundation
@preconcurrency import ApplicationServices
import AppKit
import PUSHCore

/// The two system permissions PUSH cannot work without, surfaced in Settings.
///
/// Both were already requested at launch — the microphone in `AppDelegate`, and
/// Accessibility by `HotkeyManager` when its event tap fails to form — but
/// neither was ever *reported*. A user whose hotkey silently does nothing had
/// no way to see which of the two was missing, which is the single most common
/// "PUSH is broken" state on a fresh install.
///
/// Cached rather than read from a SwiftUI `body`, for the same reason
/// `LaunchAtLoginModel` exists: a settings pane must not do work on every
/// render pass. These two reads are cheap and synchronous — unlike
/// `SMAppService.status` there is no XPC round-trip — so they run inline
/// instead of on a detached task, but they still happen on an explicit refresh
/// rather than implicitly.
///
/// Neither API publishes changes. macOS does not notify an app when someone
/// flips its switch in System Settings, so the only honest refresh points are
/// "the pane appeared" and "the app came back to the front" — the second being
/// what covers the round trip to System Settings and back. The view owns that
/// activation subscription (`onReceive`) rather than this type, so it dies with
/// the pane instead of needing a `deinit` to unhook it.
@MainActor
final class PermissionsModel: ObservableObject {

    enum Status {
        case granted
        case denied
        /// Asked for but not yet answered, or never asked.
        case notDetermined

        var isGranted: Bool { self == .granted }
    }

    @Published private(set) var microphone: Status = .notDetermined
    @Published private(set) var accessibility: Status = .notDetermined

    init() {
        refresh()
    }

    func refresh() {
        microphone = Self.microphoneStatus()
        accessibility = AXIsProcessTrusted() ? .granted : .denied
    }

    /// Opens the Privacy & Security pane. Same URL the launch-time denial alert
    /// in `AppDelegate` uses.
    func openSystemSettings() {
        open(pane: "Privacy")
    }

    /// Deep-links straight to the Microphone list, rather than the top of
    /// Privacy & Security. The wizard hands this to someone who has already
    /// denied once, so the system prompt will not come back and the only route
    /// is the switch — which is several scrolls down a long list if you land at
    /// the top of the pane.
    func openMicrophoneSettings() {
        open(pane: "Privacy_Microphone")
    }

    /// Deep-links to the Accessibility list. macOS never shows an Accessibility
    /// prompt that grants the permission outright — the dialog only offers to
    /// open this list — so this is the destination either way.
    func openAccessibilitySettings() {
        open(pane: "Privacy_Accessibility")
    }

    private func open(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            PushLogger.log("PermissionsModel: could not build System Settings URL for \(pane)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Requesting

    /// Ask for the microphone, in context.
    ///
    /// Only does anything the first time: once the answer is recorded, macOS
    /// returns it without showing anything, which is why the wizard falls back
    /// to `openMicrophoneSettings()` when the status comes back `.denied`.
    func requestMicrophone() async {
        guard microphone == .notDetermined else {
            refresh()
            return
        }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        PushLogger.log("PermissionsModel: microphone request returned granted=\(granted)")
        refresh()
    }

    /// Put up the system Accessibility dialog and open the list behind it.
    ///
    /// There is no API that grants this — `AXIsProcessTrustedWithOptions` with
    /// the prompt option only shows a dialog whose button opens System
    /// Settings. Granting it is always a manual switch, so the honest thing is
    /// to show the dialog *and* take the user where the switch is.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        PushLogger.log("PermissionsModel: prompted for accessibility")
        refresh()
    }

    // MARK: - Polling

    /// macOS publishes nothing when a permission changes, and the wizard's
    /// checkmarks are supposed to tick over the moment the user flips a switch
    /// in the window next to it — so while the wizard is on screen the only way
    /// to know is to keep asking. Both reads are cheap and synchronous (no XPC,
    /// unlike `SMAppService.status`), so a one-second beat costs nothing.
    ///
    /// Settings does not need this: it refreshes on `didBecomeActive`, which is
    /// enough when the round trip to System Settings and back is the only way
    /// the answer can change. The wizard stays visible *beside* System
    /// Settings, so it never gets that activation.
    func startPolling() {
        guard pollTimer == nil else { return }
        refresh()
        // Weak, and self-invalidating: a repeating Timer is retained by the run
        // loop, so a strong capture here would keep the model — and the window
        // that owns it — alive for the life of the process, still polling.
        //
        // The `timer` argument stays out of the `assumeIsolated` block on
        // purpose: `Timer` is not Sendable, so capturing the closure's own
        // task-isolated parameter inside a main-actor closure is a data-race
        // warning today and an error under the Swift 6 language mode. Asking
        // the isolated part whether the model is still there, and invalidating
        // outside it, keeps the same behaviour with nothing sent across.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            let isAlive = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                self.refresh()
                return true
            }
            if !isAlive { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private var pollTimer: Timer?

    private static func microphoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
