import AppKit
import SwiftUI
@preconcurrency import ApplicationServices
import PUSHCore

/// Drag-to-grant: opens a System Settings permission list and floats a card on
/// it holding PUSH, ready to be dragged into the list.
///
/// The card follows the System Settings window, hides whenever System
/// Settings is not in front, and closes itself the moment the permission is
/// granted, after ten minutes, or on its close button.
///
/// Only in a real `.app`: dropping something that is not an app bundle into
/// the list grants nothing useful, so under `swift run` this just opens the
/// pane (CLAUDE.md, "`swift run` is not the shipped app").
@MainActor
final class PermissionGuide {
    static let shared = PermissionGuide()

    enum Permission {
        case accessibility

        var title: String { "Accessibility" }
        var settingsPane: String { "Privacy_Accessibility" }
        var isGranted: Bool { AXIsProcessTrusted() }
    }

    private static let checkInterval: TimeInterval = 0.3
    private static let lifetime: TimeInterval = 10 * 60

    private var permission: Permission?
    private var panel: GuidePanel?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var startedAt = Date()
    private var isVisible = false
    private var hasPresented = false
    private var lastFrame: CGRect?

    private init() {}

    func show(_ permission: Permission) {
        dismiss()
        PermissionsModel.open(pane: permission.settingsPane)
        guard !permission.isGranted else { return }

        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            PushLogger.log("PermissionGuide: not running from an app bundle; opened the pane only")
            return
        }

        self.permission = permission
        startedAt = Date()
        panel = GuidePanel(card: PermissionGuideCard(
            permissionTitle: permission.title,
            bundleURL: bundleURL,
            onClose: { [weak self] in self?.dismiss() }
        ))
        startTracking()
        PushLogger.log("PermissionGuide: showing for \(permission.title)")
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        panel?.orderOut(nil)
        panel = nil
        permission = nil
        isVisible = false
        hasPresented = false
        lastFrame = nil
    }

    // MARK: - Tracking

    private func startTracking() {
        // Same weak, self-invalidating timer as `PermissionsModel.startPolling`.
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] timer in
            let isAlive = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                self.check()
                return true
            }
            if !isAlive { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Timer alone lags a Cmd-Tab by up to a beat; activation is instant.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    private func check() {
        guard let permission, let panel else { return }
        if permission.isGranted {
            PushLogger.log("PermissionGuide: \(permission.title) granted")
            dismiss()
            return
        }
        if Date().timeIntervalSince(startedAt) > Self.lifetime {
            dismiss()
            return
        }

        let snapshot = SettingsWindowLocator.frontmostWindow()
        switch PermissionGuideTracker.action(settingsFrame: snapshot?.frame,
                                             isVisible: isVisible, lastFrame: lastFrame) {
        case .present:
            guard let snapshot else { return }
            present(panel, at: origin(for: snapshot))
            isVisible = true
            lastFrame = snapshot.frame
        case .move:
            guard let snapshot else { return }
            panel.setFrameOrigin(origin(for: snapshot))
            lastFrame = snapshot.frame
        case .hide:
            panel.orderOut(nil)
            isVisible = false
        case .none:
            break
        }
    }

    private func origin(for snapshot: SettingsWindowLocator.Snapshot) -> CGPoint {
        PermissionGuideGeometry.cardOrigin(settingsFrame: snapshot.frame,
                                           visibleFrame: snapshot.visibleFrame,
                                           cardSize: PermissionGuideCard.size)
    }

    /// First appearance rises a few points into place — up, toward the list
    /// the user is about to drag into. Later re-appearances (coming back from
    /// another app) just show, and Reduce Motion fades.
    private func present(_ panel: NSPanel, at origin: CGPoint) {
        let target = NSRect(origin: origin, size: PermissionGuideCard.size)
        let animate = !hasPresented
        hasPresented = true

        guard animate else {
            panel.setFrame(target, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? target : target.offsetBy(dx: 0, dy: -18), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.2 : 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }
}

/// Floats on System Settings without ever taking focus from it: the user's
/// next move is a drag into *that* window, and a click on the card must not
/// pull focus away first.
private final class GuidePanel: NSPanel {
    init(card: PermissionGuideCard) {
        super.init(contentRect: NSRect(origin: .zero, size: PermissionGuideCard.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        contentView = FirstClickHostingView(rootView: card)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The close button has to answer the first click in a window that is never key.
private final class FirstClickHostingView: NSHostingView<PermissionGuideCard> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
