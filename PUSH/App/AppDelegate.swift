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

    /// Force a layout pass and match the panel to the SwiftUI content.
    ///
    /// Must run before `positionPillWindow()` whenever the pill is about to
    /// appear: `window.frame` still holds the size from the *previous* time it
    /// was shown, so centring without this centres the old width. That's what
    /// made the first dictation of a session sit off-centre — the pill was
    /// still status-sized when it was placed, then the preview's reserved width
    /// spilled out to the right, leaving the mic icon at screen centre.
    @discardableResult
    private func sizePillToContent() -> Bool {
        guard let window = pillWindow,
              let contentView = window.contentViewController?.view else { return false }

        contentView.layoutSubtreeIfNeeded()
        let newSize = contentView.fittingSize
        guard abs(newSize.width - window.frame.width) > 0.5
                || abs(newSize.height - window.frame.height) > 0.5 else { return false }

        window.setContentSize(newSize)
        return true
    }

    /// Re-measure and grow/shrink the panel around its own centre, so the pill
    /// stays bottom-centered instead of creeping rightward off the anchor.
    private func refitPillWindow() {
        guard let window = pillWindow else { return }
        let centerX = window.frame.midX
        guard sizePillToContent() else { return }
        window.setFrameOrigin(NSPoint(x: centerX - window.frame.width / 2,
                                      y: window.frame.minY))
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
                    self.sizePillToContent()   // before centring — see the note there
                    self.positionPillWindow()
                }
                self.pillWindow?.orderFront(nil)
                // Re-fit on every state change, not just on appear. The status
                // text changes width while the pill is already on screen
                // ("Loading model…" → "Warming up…" → "Listening"), and without
                // this the window keeps its old size and clips the longer
                // string — "Warming up…" rendered cut off. Deferred a turn so
                // SwiftUI has applied the change before we measure it.
                DispatchQueue.main.async { self.refitPillWindow() }
            } else {
                self.pillWindow?.orderOut(nil)
            }
        }
    }

    /// Sparkle stalls the app for around four seconds when it starts — measured,
    /// and not the permission modal: it happens with checks already enabled.
    /// The ASR model now loads in ~0.1s, so starting the updater straight after
    /// put that stall directly under the user's first hotkey press, which felt
    /// exactly like the startup hang it replaced. Push it well past the point
    /// where someone would plausibly be dictating; update checks are daily, so
    /// a minute's delay costs nothing.
    ///
    /// Timer rather than Task.sleep on purpose: a run-loop timer still fires if
    /// something wedges the main queue, which is the failure mode this whole
    /// area keeps producing.
    private func scheduleUpdaterStart() {
        let timer = Timer(timeInterval: 60, repeats: false) { _ in
            MainActor.assumeIsolated { UpdaterManager.shared.start() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func preloadModels() {
        Task { @MainActor in
            // ModelLoader handles status, warmup, and failure surfacing.
            try? await ModelLoader.activate(AppState.shared.selectedWhisperModel)

            // Only now start Sparkle. `startUpdater` can put up a modal (an
            // update prompt, a permission request, an error), and a modal runs
            // its own loop *inside* the main-queue block that opened it. The
            // main queue is serial, so until that block returns every later
            // DispatchQueue.main.async and every `Task { @MainActor }`
            // continuation is stuck behind it — including the one that sets
            // isModelReady. That deadlocked startup: the engine finished
            // loading, the app never noticed, the pill sat on "Loading model…"
            // and the hotkey did nothing, with no feedback about why.
            // Starting it after the model is serving keeps dictation working
            // no matter what Sparkle decides to show.
            // Pay the capture path's lazy setup now, not on the user's first
            // press. Runs before the updater is scheduled so it can't be
            // delayed behind it.
            await AudioRecorder.shared.prewarm()

            scheduleUpdaterStart()

        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appStateDidChange = Notification.Name("appStateDidChange")
}
