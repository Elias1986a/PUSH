import Foundation
import Combine
import Sparkle

/// Owns Sparkle's updater for the app's lifetime and exposes a SwiftUI-friendly
/// "Check for Updates…" action.
///
/// Sparkle reads `SUFeedURL` and `SUPublicEDKey` from Info.plist; this type just
/// starts the updater and forwards the user-initiated check. Instantiated once at
/// launch (see `AppDelegate`) so scheduled background checks run even before the
/// menu is ever opened.
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController

    /// Mirrors `SPUUpdater.canCheckForUpdates` so the menu item can disable itself
    /// while a check is already in flight.
    @Published private(set) var canCheckForUpdates = false

    private init() {
        // startingUpdater: true → begin scheduled checks immediately using the
        // feed URL / public key from Info.plist. The standard controller also
        // provides Sparkle's default UI (update prompt, progress, install).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Triggers a user-initiated update check (shows "you're up to date" when none).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
