import SwiftUI
import PUSHCore

@main
struct PUSHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        // No `MenuBarExtra`: the status item and its popover are AppKit's, in
        // `MenuBarController`, because SwiftUI's version cannot produce the
        // system's own rounded panel chrome. This scene exists so the Settings
        // window keeps its standard behaviour and ⌘, shortcut.
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
