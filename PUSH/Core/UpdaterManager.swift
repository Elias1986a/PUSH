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

    private var hasStarted = false

    private init() {
        // startingUpdater: false is load-bearing. `startUpdater` can put up a
        // modal (permission request, update prompt, error), and a modal runs
        // its own loop *inside* the main-queue block that opened it. The main
        // queue is serial, so nothing queued behind it ever runs — including
        // the continuation that marks the model ready. Constructing this type
        // must therefore be free of side effects: `MenuBarView` holds the
        // singleton, so it gets built while the app is still starting up.
        // `start()` decides when it is safe to actually begin.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Begin scheduled checks. Call once the app is serving dictation, so a
    /// modal from Sparkle can never block startup. Safe to call more than once.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        controller.startUpdater()
        PushLogger.log("UpdaterManager: Sparkle updater started")
    }

    /// Triggers a user-initiated update check (shows "you're up to date" when none).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
