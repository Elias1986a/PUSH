import SwiftUI
import AVFoundation
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var pillWindow: NSWindow?
    /// Screen-centre the pill is anchored to, captured when it appears.
    private var pillCenterX: CGFloat?

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
        // Let AppKit follow SwiftUI's own ideal size instead of us re-measuring
        // by hand on each state change. Every hand-rolled refit had to name the
        // moments worth re-measuring, and each missed one clipped the pill —
        // "Warming up…" rendered cut off because the status text changed width
        // while the window was already on screen. This tracks all of them.
        hostingController.sizingOptions = [.preferredContentSize]

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
        // SwiftUI resizes the window from the bottom-left, so anything that
        // widens the pill would walk it rightward off its anchor. Re-centre on
        // the anchor we chose when it appeared.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pillDidResize),
            name: NSWindow.didResizeNotification,
            object: window
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
        guard let screen else { return }
        // Centre on the physical screen, not `visibleFrame` — a Dock pinned to
        // the left or right shrinks visibleFrame and would push the pill
        // off-centre relative to the display.
        pillCenterX = screen.frame.midX
        let y = screen.visibleFrame.minY + 10  // 10px from bottom
        window.setFrameOrigin(NSPoint(x: screen.frame.midX - window.frame.width / 2, y: y))
    }

    /// Keep the pill centered on its anchor as SwiftUI resizes it. Re-centring
    /// on the stored anchor rather than the window's own midX means repeated
    /// resizes can't accumulate drift.
    @objc private func pillDidResize() {
        guard let window = pillWindow, let centerX = pillCenterX else { return }
        let x = centerX - window.frame.width / 2
        guard abs(window.frame.minX - x) > 0.5 else { return }
        window.setFrameOrigin(NSPoint(x: x, y: window.frame.minY))
    }

    @objc private func screenLayoutChanged() {
        DispatchQueue.main.async {
            self.positionPillWindow()
        }
    }

    @objc private func updatePillVisibility() {
        DispatchQueue.main.async {
            let state = AppState.shared
            if state.pillShouldShow {
                // Re-anchor only when appearing, so the pill doesn't jump
                // screens mid-dictation if the pointer moves. Lay out first:
                // the window still holds the size from the last time it was
                // shown, and centring the old width is what put the first
                // dictation of a session off-centre.
                if !(self.pillWindow?.isVisible ?? false) {
                    self.pillWindow?.contentViewController?.view.layoutSubtreeIfNeeded()
                    self.positionPillWindow()
                }
                self.pillWindow?.orderFront(nil)
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
            // Clear the warming indicator however this ends — a failed model load
            // must not leave the pill claiming it is still warming up forever.
            defer {
                AppState.shared.isPrewarming = false
                PushLogger.log("AppDelegate: warm-up complete, indicator cleared")
            }

            // Start the audio warm-ups immediately, in parallel with the model
            // load, rather than after it. Binding the input HAL measured 4.3s on
            // a USB mic — it is by far the longest pole, and every moment it
            // starts earlier is a moment shaved off the window where a press
            // finds the app deaf. The model load only takes ~0.1s, but it was
            // 0.1s the microphone was not warming.
            async let capture: Void = AudioRecorder.shared.prewarm()
            async let chirp: Void = SoundPlayer.shared.prewarm()

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
            // Warm in press-path order — chirp, then capture — because the whole
            // sequence takes a few seconds and a press part-way through only gets
            // the benefit of whatever finished first. The chirp is cheap and comes
            // first on the press path; the capture engine and the VAD's CoreML
            // load are the slow ones.
            // Both awaited: the indicator must not clear until every part is
            // genuinely warm. The chirp used to be fire-and-forget, so the pill
            // went away about a second before it finished.
            await capture
            await chirp

            scheduleUpdaterStart()

        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appStateDidChange = Notification.Name("appStateDidChange")
}
