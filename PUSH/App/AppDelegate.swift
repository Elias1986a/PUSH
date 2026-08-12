import SwiftUI
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var pillWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // If a previous run died mid-dictation while the output volume was
        // ducked, put the user's volume back rather than leaving it quiet.
        MediaController.shared.restoreVolumeIfInterrupted()

        // Request permissions
        requestMicrophonePermission()

        // Initialize hotkey manager (will handle accessibility permission itself)
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.startListening()

        // Setup floating pill window
        setupFloatingPillWindow()

        // Start Sparkle auto-updater so scheduled checks run even before the
        // menu bar item is first opened.
        _ = UpdaterManager.shared

        // Pre-load Whisper model in background (will download if needed)
        preloadModels()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stopListening()
        // Don't leave the user's audio quieted if they quit mid-dictation.
        MediaController.shared.endDictation()
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.showPermissionAlert(for: "Microphone")
                }
            }
        }
    }

    private func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "\(permission) Access Required"
        alert.informativeText = "PUSH needs \(permission.lowercased()) access to function. Please grant access in System Settings > Privacy & Security."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Floating Pill Window

    /// Wide enough for a full line of live transcript at 11pt. The window is
    /// transparent and ignores mouse events, so the unused width costs nothing.
    private static let pillWindowWidth: CGFloat = 520
    private static let pillMinimumHeight: CGFloat = 32

    private func setupFloatingPillWindow() {
        let pillView = FloatingPillView()
            .environmentObject(AppState.shared)

        let hostingController = NSHostingController(rootView: pillView)

        // Use NSPanel with .nonactivatingPanel so showing it doesn't activate the app
        // or pull the user out of full-screen mode
        let window = NSPanel(contentViewController: hostingController)
        window.styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.isFloatingPanel = true

        // Fixed-width panel: the capsule grows and shrinks inside it as live
        // text arrives, so the window never resizes or re-centres mid-sentence.
        // Height still comes from layout — the pill is always a single line.
        hostingController.view.layoutSubtreeIfNeeded()
        let contentHeight = max(hostingController.view.fittingSize.height, Self.pillMinimumHeight)
        window.setContentSize(NSSize(width: Self.pillWindowWidth, height: contentHeight))

        self.pillWindow = window
        positionPillWindow()

        // Observe app state to show/hide pill
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePillVisibility),
            name: .appStateDidChange,
            object: nil
        )
        // Reposition when displays are added/removed/rearranged
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Evaluate visibility once now. AppState's `didSet` observers don't fire
        // during its initialization, so no .appStateDidChange is posted for the
        // initial `isModelReady == false` — without this the "Loading model..."
        // pill never appears during a cold start.
        updatePillVisibility()
    }

    /// Bottom-center of the screen the pointer is on — dictation happens where
    /// the user is working, which isn't necessarily the launch-time main screen.
    private func positionPillWindow() {
        guard let window = pillWindow else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screenFrame = screen?.visibleFrame else { return }
        let windowSize = window.frame.size
        // Clamp to the screen: the panel is wider than the visible capsule, so
        // on a narrow display centring alone could push it off the left edge.
        let x = max(screenFrame.minX, screenFrame.midX - windowSize.width / 2)
        let y = screenFrame.minY + 10  // 10px from bottom
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func screenLayoutChanged() {
        DispatchQueue.main.async {
            self.positionPillWindow()
        }
    }

    @objc private func updatePillVisibility() {
        DispatchQueue.main.async {
            let state = AppState.shared
            if state.isListening || state.isProcessing || !state.isModelReady || state.isWarmingUp {
                // Re-anchor only when appearing, so the pill doesn't jump
                // screens mid-dictation if the pointer moves.
                if !(self.pillWindow?.isVisible ?? false) {
                    self.positionPillWindow()
                }
                self.pillWindow?.orderFront(nil)
            } else {
                self.pillWindow?.orderOut(nil)
            }
        }
    }

    private func preloadModels() {
        Task { @MainActor in
            // ModelLoader handles status, warmup, and failure surfacing.
            try? await ModelLoader.activate(AppState.shared.selectedWhisperModel)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appStateDidChange = Notification.Name("appStateDidChange")
}
