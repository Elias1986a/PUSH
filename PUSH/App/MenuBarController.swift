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
    /// When the popover last closed. A transient popover closes on the
    /// mouse-down of any click outside it, and the status item counts as
    /// outside, so the icon's own action (sent on mouse-up) found it already
    /// shut and opened it again: a click on the icon never closed the menu
    /// (user report, 2026-10-12).
    private var closedAt = Date.distantPast

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
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environment(AppState.shared))
        self.popover = popover
    }

    @objc private func updateIcon() {
        let state = AppState.shared
        // Ready means the features that are on: with dictation off the speech
        // model never loads, and a Type-only PUSH showed an hourglass forever.
        let ready = state.dictationEnabled ? state.isModelReady : (!state.typeEnabled || state.typingModelReady)
        statusItem?.button?.image = Self.icon(ready: ready, dictation: state.dictationEnabled, typing: state.typeEnabled)
    }

    /// One symbol per feature that is on: the microphone for dictation, a
    /// text cursor for Type, both side by side when both are (the user's
    /// design, 2026-10-11; one or the other alone, 2026-10-12). With neither
    /// on, the microphone, so PUSH is still findable.
    static func icon(ready: Bool, dictation: Bool, typing: Bool) -> NSImage? {
        guard ready else { return template(NSImage(systemSymbolName: "hourglass", accessibilityDescription: "PUSH")) }
        guard let mic = NSImage(systemSymbolName: "music.mic", accessibilityDescription: "PUSH") else { return nil }
        guard typing else { return template(mic) }
        // An I-beam drawn by hand: the SF cursor symbols all carry an "A".
        let gap: CGFloat = 1.5, beam: CGFloat = 5
        let micWidth = dictation ? mic.size.width + gap : 0
        // Alone, the beam gets a little room either side so the click target
        // and spacing match the other menu bar icons.
        let pad: CGFloat = dictation ? 0 : 3
        let size = NSSize(width: micWidth + beam + pad * 2, height: max(mic.size.height, 16))
        let image = NSImage(size: size, flipped: false) { rect in
            if dictation {
                mic.draw(in: CGRect(x: 0, y: (rect.height - mic.size.height) / 2,
                                    width: mic.size.width, height: mic.size.height))
            }
            let x = micWidth + pad + beam / 2
            let top = rect.midY + 6, bottom = rect.midY - 6
            let path = NSBezierPath()
            path.lineWidth = 1.3
            path.lineCapStyle = .round
            path.move(to: CGPoint(x: x, y: bottom)); path.line(to: CGPoint(x: x, y: top))
            for y in [top, bottom] {
                path.move(to: CGPoint(x: x - beam / 2, y: y)); path.line(to: CGPoint(x: x + beam / 2, y: y))
            }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.accessibilityDescription = "PUSH"
        return template(image)
    }

    /// Template so macOS tints it for the menu bar's appearance, light or
    /// dark, rather than us picking a colour that is wrong half the time.
    private static func template(_ image: NSImage?) -> NSImage? {
        image?.isTemplate = true
        return image
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // This click's mouse-down just closed it.
        guard Date().timeIntervalSince(closedAt) > 0.3 else { return }
        // An accessory app has to ask for the front, or the popover opens
        // without key focus and its controls do not respond to the keyboard.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    #if DEBUG
    /// `PUSH_OPEN_MENU=1` opens the popover on launch, for screenshots.
    func openIfRequested() {
        guard ProcessInfo.processInfo.environment["PUSH_OPEN_MENU"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.togglePopover() }
    }
    #endif

    /// Close the panel after an action that opens something else, so the popover
    /// is not left hanging over the window it just summoned.
    func dismiss() {
        popover?.performClose(nil)
    }
}

extension MenuBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        closedAt = Date()
    }
}
