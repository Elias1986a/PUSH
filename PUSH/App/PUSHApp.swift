import SwiftUI
import PUSHCore

@main
struct PUSHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Every window this app shows is an AppKit one, created by
        // `AppDelegate` (the pill), `MenuBarController` (the status item and
        // its popover), `OnboardingWindowController` and
        // `SettingsWindowController`.
        //
        // SwiftUI's own scenes could not do the job here. `MenuBarExtra` gives
        // no way to get the system's rounded popover chrome, and once it was
        // gone the `Settings` scene stopped materialising at all —
        // `showSettingsWindow:` reported success while `NSApp.windows` held no
        // settings window to show.
        //
        // `App` still requires a scene, so this is an empty one. It is never
        // opened; it exists to satisfy the protocol.
        Settings { EmptyView() }
    }
}
