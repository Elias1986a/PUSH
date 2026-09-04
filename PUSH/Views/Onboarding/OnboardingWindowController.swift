import SwiftUI
import AppKit
import PUSHCore

/// Owns the welcome wizard's window and the "has this user seen it" flag.
///
/// A window rather than a sheet or a popover because there is nothing to
/// attach one to: PUSH has no main window, and the menu bar's popover closes
/// the moment the user clicks away — which on step 2 is exactly what they are
/// asked to do (go to System Settings and come back), and on step 3 is where
/// the sandbox has to keep focus.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    /// Fixed size — the wizard is laid out for it and there is nothing here
    /// worth resizing.
    static let contentSize = CGSize(width: 640, height: 560)

    private static let seenKey = "hasSeenOnboarding"

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    /// Whether this launch should open the wizard on its own.
    ///
    /// Keyed on a flag rather than on "are permissions missing", so someone who
    /// deliberately declined a permission is not met by the same wizard at
    /// every launch for the rest of the app's life.
    static var isPending: Bool {
        !UserDefaults.standard.bool(forKey: seenKey)
    }

    /// Records that the wizard has been seen, so it does not reappear. Set when
    /// the user finishes *or* dismisses it — a wizard that comes back after you
    /// closed it is a worse first impression than no wizard at all.
    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// Open the wizard, or bring it forward if it is already up.
    func show() {
        if let window {
            activate(window)
            return
        }

        let hosting = NSHostingController(
            rootView: OnboardingView(onFinish: { [weak self] in self?.finish() })
                .environmentObject(AppState.shared)
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to PUSH"
        // No resize and no minimise: the content is a fixed-size flow, and an
        // accessory app has no Dock icon to restore a minimised window from.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(Self.contentSize)
        window.center()
        // We hold the only reference and reopen by building a fresh window, so
        // AppKit must not release this one out from under us on close.
        window.isReleasedWhenClosed = false

        // Notification rather than NSWindowDelegate, so this type does not have
        // to be an NSObject purely to learn that a window closed.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Closing with the red button counts as having seen it.
                Self.markSeen()
                // The wizard was the reason HotkeyManager stayed quiet about
                // Accessibility; hand that back now that it is gone, so someone
                // who skipped still gets the normal system prompt.
                HotkeyManager.suppressesAccessibilityPrompt = false
                self?.forgetWindow()
                PushLogger.log("Onboarding: wizard closed")
            }
        }

        self.window = window
        activate(window)
        PushLogger.log("Onboarding: wizard shown")
    }

    /// `LSUIElement` apps do not come to the front on their own, and this
    /// window has to be key for step 3 to work at all: the sandbox field only
    /// receives the pasted transcript if it holds focus.
    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        Self.markSeen()
        // `windowWillClose` does the rest of the teardown.
        window?.close()
    }

    private func forgetWindow() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        window = nil
    }
}
