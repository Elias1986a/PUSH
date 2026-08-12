import SwiftUI
import AVFoundation
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var pillWindow: NSWindow?
    private var previewCancellable: AnyCancellable?

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

        // Force a layout to get the actual window size
        hostingController.view.layoutSubtreeIfNeeded()
        window.setContentSize(hostingController.view.fittingSize)

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

        // The pill is a borderless panel sized once from `fittingSize`, so it
        // does not resize itself when the live preview appears. The preview
        // claims a fixed width, so in practice this fires twice per dictation —
        // once when the first partial widens the pill, once when it clears —
        // and the width check below no-ops on every partial in between.
        // Not routed through .appStateDidChange on purpose: that notification
        // drives show/hide, which shouldn't run every second.
        previewCancellable = AppState.shared.$livePartialText
            .removeDuplicates()
            .sink { [weak self] _ in
                // The published value hasn't been applied to the view yet; let
                // SwiftUI render this frame before measuring the new fit.
                DispatchQueue.main.async { self?.refitPillWindow() }
            }

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
        guard let screen else { return }
        let windowSize = window.frame.size
        // Centre on the physical screen, not `visibleFrame` — a Dock pinned to
        // the left or right shrinks visibleFrame and would push the pill
        // off-centre relative to the display.
        let x = screen.frame.midX - windowSize.width / 2
        let y = screen.visibleFrame.minY + 10  // 10px from bottom
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Re-measure the SwiftUI content and grow/shrink the panel around its own
    /// center, so the pill stays bottom-centered as live text widens it instead
    /// of creeping rightward off the anchor.
    private func refitPillWindow() {
        guard let window = pillWindow,
              let contentView = window.contentViewController?.view else { return }

        contentView.layoutSubtreeIfNeeded()
        let newSize = contentView.fittingSize
        let current = window.frame
        guard abs(newSize.width - current.width) > 0.5 else { return }

        let x = current.midX - newSize.width / 2
        window.setFrame(
            NSRect(x: x,
                   y: current.minY,
                   width: newSize.width,
                   height: newSize.height),
            display: true,
            animate: false
        )
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
