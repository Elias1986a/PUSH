import Foundation
import ServiceManagement

/// Cached "start at login" state.
///
/// `SMAppService.mainApp.status` is a synchronous XPC round-trip to the
/// Service Management daemon, measured at 61-66ms in this app — and it does
/// not get cheaper when warm, because there is nothing to warm. Read straight
/// from a SwiftUI `body` (which is what `LaunchAtLogin.Toggle` does) that cost
/// lands on the main thread on every render pass, several times per
/// interaction, which is why the General tab appeared to hang when opened.
///
/// Blocking the main thread is also how this app loses its hotkey: macOS
/// disables a CGEvent tap whose run loop stops servicing it. A settings tab
/// should not be able to do that.
///
/// So the status is read once, off the main thread, and cached. Writes go the
/// same way and re-read afterwards, so the toggle reflects what actually
/// happened rather than what was asked for.
@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var isEnabled = false

    private var hasLoaded = false

    /// Safe to call on every appearance; only the first does the work.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isEnabled = await Self.readStatus()
    }

    func set(_ newValue: Bool) {
        // Optimistic, so the toggle responds immediately; corrected below if
        // the daemon disagrees.
        isEnabled = newValue

        Task { [weak self] in
            let actual = await Self.write(newValue)
            await MainActor.run { self?.isEnabled = actual }
        }
    }

    private static func readStatus() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            SMAppService.mainApp.status == .enabled
        }.value
    }

    /// Applies the change and returns the status the daemon actually reports.
    private static func write(_ enabled: Bool) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            do {
                if enabled {
                    // Re-registering while already enabled throws; clear first.
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                PushLogger.log("LaunchAtLogin: failed to set \(enabled) — \(error.localizedDescription)")
            }
            return SMAppService.mainApp.status == .enabled
        }.value
    }
}
