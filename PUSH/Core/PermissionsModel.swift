import Foundation
import AVFoundation
import ApplicationServices
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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else {
            PushLogger.log("PermissionsModel: could not build System Settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func microphoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
