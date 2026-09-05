import SwiftUI
import AppKit
import PUSHCore

/// Owns the settings window.
///
/// SwiftUI's `Settings` scene does not work in this app. With `MenuBarExtra`
/// gone the scene never materialises: `showSettingsWindow:` reports success —
/// something in the responder chain claims the action — but enumerating
/// `NSApp.windows` afterwards shows only the status item, the pill panel and
/// the popover. There is no settings window to order front, and no supported
/// way to make SwiftUI build one from outside its scene graph.
///
/// So the window is ours, the same as the welcome wizard's. The content is
/// still `SettingsView`; only who creates the window changed.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func show() {
        if let window {
            activate(window)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView().environment(AppState.shared))

        let window = NSWindow(contentViewController: hosting)
        window.title = "PUSH Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 820, height: 620))
        // Remembers position and size across launches, which is what the
        // SwiftUI scene did for free and what the user will miss if it stops.
        window.setFrameAutosaveName("PUSHSettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forgetWindow() }
        }

        self.window = window
        activate(window)
        PushLogger.log("Settings: window opened")
    }

    /// An accessory app does not come to the front on its own, and a settings
    /// window nobody can type into is not much use.
    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func forgetWindow() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        window = nil
    }
}
