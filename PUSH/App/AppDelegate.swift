import SwiftUI
import AVFoundation
import Combine
import PUSHCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var pillWindow: NSWindow?
    /// Screen-centre the pill is anchored to, captured when it appears.
    private var pillCenterX: CGFloat?
    /// Screen top the pill hangs from, or nil at the bottom placement.
    private var pillTopY: CGFloat?
    /// The placement the window was last positioned for.
    private var positionedPlacement: AppState.PillPosition?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Say out loud what `LSUIElement` says in the shipped app's Info.plist:
        // a menu bar app with no Dock icon that can still be brought to the
        // front when it has something to show.
        //
        // Load-bearing for `swift run`. SwiftPM builds a bare executable with
        // no Info.plist, so `LSUIElement` never applies and macOS assigns the
        // process `.prohibited` — an app that cannot be activated and whose
        // windows cannot become key, measured as
        // `policy=2 isActive=false isKey=false`. Everything that needs focus
        // then fails silently in development only: the welcome wizard's
        // dictation sandbox never receives its own paste, and the text lands in
        // whatever app really is frontmost (Terminal, typically) — which reads
        // as "dictation is broken" rather than "this build has no bundle".
        //
        // A no-op in the distribution build, which is already `.accessory`.
        if NSApp.activationPolicy() != .accessory {
            let promoted = NSApp.setActivationPolicy(.accessory)
            PushLogger.log("AppDelegate: activation policy set to .accessory (\(promoted)) — unbundled build")
        }

        // If a previous run died mid-dictation while the output volume was
        // ducked, put the user's volume back rather than leaving it quiet.
        MediaController.shared.restoreVolumeIfInterrupted()

        // On a first launch the welcome wizard owns both permission prompts, so
        // that neither arrives as a bare system dialog from an app with no Dock
        // icon and no window — the state the audit found reads as a crash.
        // Every later launch behaves exactly as before.
        let showingWizard = OnboardingWindowController.isPending
        HotkeyManager.suppressesAccessibilityPrompt = showingWizard

        if !showingWizard {
            requestMicrophonePermission()
        }

        // Initialize hotkey manager (will handle accessibility permission itself
        // unless the wizard has taken that over for this launch). Started either
        // way: its retry timer is what picks the permission up once granted, so
        // the hotkey comes alive the moment the user flips the switch on step 2,
        // without a relaunch.
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.startListening()

        // The menu bar status item and its popover.
        MenuBarController.shared.install()

        // Setup floating pill window
        setupFloatingPillWindow()

        // Pre-load the speech model in background (will download if needed)
        preloadModels()

        if showingWizard {
            showOnboarding()
        }

        #if DEBUG
        openSettingsIfRequested()
        #endif
    }

    /// Show the welcome wizard once the app has finished coming up.
    ///
    /// Deferred a beat rather than shown inline: `applicationDidFinishLaunching`
    /// is still on the launch path, and activating a window from inside it
    /// races the menu bar extra's own setup.
    private func showOnboarding() {
        DispatchQueue.main.async {
            OnboardingWindowController.shared.show()
        }
    }

    #if DEBUG
    /// `PUSH_OPEN_SETTINGS=1 swift run` opens the settings window on launch.
    ///
    /// This app is `LSUIElement`, so its only door to Settings is the menu bar
    /// extra — which means checking a settings change costs a menu click, and
    /// scripting that click is unreliable because the window closes again as
    /// soon as the app loses focus. DEBUG-only: it cannot reach a release build.
    private func openSettingsIfRequested() {
        guard ProcessInfo.processInfo.environment["PUSH_OPEN_SETTINGS"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            NSApp.activate(ignoringOtherApps: true)
            // Renamed in macOS 14; try the modern selector first and fall back
            // so this keeps working either way.
            let opened = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                || NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            PushLogger.log("AppDelegate: PUSH_OPEN_SETTINGS opened settings = \(opened)")
        }
    }
    #endif

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
            .environment(AppState.shared)

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

    /// Centered on the screen the pointer is on — dictation happens where the
    /// user is working, which isn't necessarily the launch-time main screen —
    /// and pinned to whichever edge the placement asks for.
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
        positionedPlacement = AppState.shared.pillPosition

        if AppState.shared.pillPosition == .top {
            // The tab has to draw over the menu bar strip it descends from.
            // `.statusBar` sits one level above `.mainMenu`, which the menu bar
            // itself can still win; the extra levels are what NotchIsland-style
            // HUDs use to own that strip without private API.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            AppState.shared.pillTopInset = topClearance(for: screen)
            // Let SwiftUI re-measure with the inset it was just handed, so the
            // top edge is pinned against the real height rather than the
            // previous one.
            window.contentViewController?.view.layoutSubtreeIfNeeded()
            pillTopY = screen.frame.maxY
            window.setFrameOrigin(NSPoint(
                x: screen.frame.midX - window.frame.width / 2,
                y: screen.frame.maxY - window.frame.height
            ))
        } else {
            window.level = .statusBar
            pillTopY = nil
            window.setFrameOrigin(NSPoint(
                x: screen.frame.midX - window.frame.width / 2,
                y: screen.visibleFrame.minY + 10
            ))
        }
    }

    /// What the top placement has to clear before it can draw.
    ///
    /// Only the notch earns a full band: it is hardware, and drawing under it
    /// puts text behind the camera. The menu bar is not — the tab is drawn
    /// over it, and the centre of the menu bar where the tab sits is empty on
    /// every standard setup — so reserving its full height on a display
    /// without a notch just spends 30 points of the user's desktop to clear
    /// something that isn't there.
    private func topClearance(for screen: NSScreen) -> CGFloat {
        let notch = screen.safeAreaInsets.top
        return notch > 0 ? notch : Self.bareEdgeClearance
    }

    /// Breathing room above the content on a display with no notch — enough
    /// that the text isn't jammed against the screen edge, and no more.
    private static let bareEdgeClearance: CGFloat = 6

    /// Keep the pill on its anchors as SwiftUI resizes it. Re-anchoring against
    /// the stored values rather than the window's own frame means repeated
    /// resizes can't accumulate drift.
    ///
    /// The top placement has to re-pin vertically too: AppKit resizes from the
    /// bottom-left, so a pill that grows taller — the preview wrapping, the
    /// status text changing — would push its top edge down off the screen edge
    /// and open a gap above itself.
    @objc private func pillDidResize() {
        guard let window = pillWindow, let centerX = pillCenterX else { return }
        let x = centerX - window.frame.width / 2
        let y = pillTopY.map { $0 - window.frame.height } ?? window.frame.minY
        guard abs(window.frame.minX - x) > 0.5 || abs(window.frame.minY - y) > 0.5 else { return }
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
            if state.pillShouldShow {
                // Re-anchor only when appearing, so the pill doesn't jump
                // screens mid-dictation if the pointer moves. Lay out first:
                // the window still holds the size from the last time it was
                // shown, and centring the old width is what put the first
                // dictation of a session off-centre.
                // A placement change is the one thing worth re-anchoring a pill
                // that's already on screen for: it has to cross the display.
                if !(self.pillWindow?.isVisible ?? false)
                    || self.positionedPlacement != state.pillPosition {
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

            // Behind the warm-up: syncing is never worth delaying a first press.
            CloudSync.shared.start()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appStateDidChange = Notification.Name("appStateDidChange")
}
