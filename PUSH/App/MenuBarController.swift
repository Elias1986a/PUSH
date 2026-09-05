import AppKit
import SwiftUI
import PUSHCore

/// The menu bar status item and the panel it drops down.
///
/// AppKit rather than SwiftUI's `MenuBarExtra`, after trying both.
/// `.menuBarExtraStyle(.menu)` renders custom content inside an `NSMenu`,
/// which adapts it awkwardly and drops menu behaviours like keyboard
/// navigation. `.menuBarExtraStyle(.window)` hands the content a plain opaque
/// panel with square corners, and SwiftUI exposes no API to shape it — the
/// rounded corners, shadow, vibrancy and click-outside dismissal that make a
/// status item panel look like part of the system all belong to `NSPopover`,
/// and masking a layer inside the square panel only imitates them.
///
/// So the status item is ours. The content is still the same SwiftUI view;
/// only the chrome changed.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private override init() { super.init() }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        updateIcon()

        // The icon is the one piece of PUSH always on screen, so it carries the
        // loading state. AppState posts this whenever readiness changes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateIcon),
            name: .appStateDidChange,
            object: nil)

        let popover = NSPopover()
        popover.behavior = .transient          // closes when you click away
        popover.animates = false               // a menu does not animate open
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environment(AppState.shared))
        self.popover = popover
    }

    @objc private func updateIcon() {
        let ready = AppState.shared.isModelReady
        statusItem?.button?.image = Self.icon(ready: ready)
    }

    private static func icon(ready: Bool) -> NSImage? {
        let name = ready ? "music.mic" : "hourglass"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "PUSH")
        // Template so macOS tints it for the menu bar's appearance, light or
        // dark, rather than us picking a colour that is wrong half the time.
        image?.isTemplate = true
        return image
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // An accessory app has to ask for the front, or the popover opens
        // without key focus and its controls do not respond to the keyboard.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    /// Close the panel after an action that opens something else, so the popover
    /// is not left hanging over the window it just summoned.
    func dismiss() {
        popover?.performClose(nil)
    }
}
