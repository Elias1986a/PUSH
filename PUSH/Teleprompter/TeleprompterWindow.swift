import AppKit
import SwiftUI
import PUSHCore

/// The prompter's window: a panel hanging off the top edge of the screen,
/// excluded from screen capture.
///
/// Its own window rather than the dictation pill's. The pill sets
/// `ignoresMouseEvents` and a sharing type that suit dictation, and the
/// prompter needs neither — keeping them apart means this feature cannot
/// regress the one people already rely on.
@MainActor
final class TeleprompterWindow {
    static let shared = TeleprompterWindow()

    private var panel: NSPanel?
    private var settingsObserver: NSObjectProtocol?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Show / hide

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        applySharingType()
        position(panel)

        // `orderFrontRegardless`, never `makeKeyAndOrderFront` plus
        // `NSApp.activate`. Activating would pull focus out of whatever is
        // being recorded — which is what the reference implementation does, and
        // is exactly wrong for a prompter.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Re-read the hide-from-recording setting. Cheap enough to call whenever
    /// it might have changed.
    func applySharingType() {
        panel?.sharingType = TeleprompterState.shared.hideFromScreenRecording ? .none : .readOnly
    }

    /// Re-measure after a size change or a display rearrangement.
    func reposition() {
        guard let panel else { return }
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        position(panel)
    }

    // MARK: - Building

    private func makePanel() -> NSPanel {
        let screen = targetScreen()
        let root = TeleprompterView(
            settings: TeleprompterState.shared,
            session: TeleprompterSession.shared,
            topInset: topClearance(for: screen)
        )

        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = [.preferredContentSize]

        // `.nonactivatingPanel` is the load-bearing flag: showing the prompter
        // must not activate PUSH, or it drops the user out of the full-screen
        // app they are recording.
        let panel = NSPanel(contentViewController: controller)
        panel.styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        // Same reasoning as the pill's top placement: the panel descends from
        // the menu bar strip, so it has to outrank the menu bar to draw there.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

        controller.view.layoutSubtreeIfNeeded()
        return panel
    }

    // MARK: - Placement

    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func position(_ panel: NSPanel) {
        let screen = targetScreen()
        panel.setFrameOrigin(NSPoint(
            x: screen.frame.midX - panel.frame.width / 2,
            // Flush with the physical top edge. The panel's own top corners are
            // square, so there is no radius peeking out that needs hiding —
            // which is the fudge the reference implementation needs, and the
            // one its author notes breaks multi-display placement.
            y: screen.frame.maxY - panel.frame.height
        ))
    }

    /// What the panel has to clear before it can draw: the camera housing on a
    /// notched display, or a little breathing room on one without.
    private func topClearance(for screen: NSScreen) -> CGFloat {
        let notch = screen.safeAreaInsets.top
        return notch > 0 ? notch : 6
    }
}
