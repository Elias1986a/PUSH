import SwiftUI
import PUSHCore

@main
struct PUSHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // The menu bar item is the one piece of UI that's always on screen,
            // so it carries the loading state: an hourglass until a model is
            // actually serving. The pill says "Loading model…" too, but it only
            // appears over the active app and is easy to miss at login.
            if appState.isModelReady {
                // Matches the app icon's microphone; see MicGlyph.
                Image(nsImage: MicGlyph.menuBarImage)
            } else {
                Image(systemName: "hourglass")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

    }
}
