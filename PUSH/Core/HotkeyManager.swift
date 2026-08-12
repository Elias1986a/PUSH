import Foundation
import Carbon
import Cocoa
@preconcurrency import ApplicationServices

/// Manages global hotkey detection for push-to-talk functionality
/// Listens for Right Option key press/release events
@MainActor
final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var isRightOptionPressed = false
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var retryTimer: Timer?
    private var releaseWatchdog: Timer?
    private var releaseMissTicks = 0

    // Tracks whether we're actively recording (hotkey or wake word).
    // Accessed from event tap callback (main run loop) and @MainActor methods.
    // nonisolated(unsafe) because the event tap callback isn't formally @MainActor,
    // but both contexts run on the main thread so there's no actual data race.
    nonisolated(unsafe) private var isCurrentlyRecording = false
    // Tracks whether we're actively processing (transcribing audio).
    // Needed separately from AppState.isProcessing because the event tap callback
    // can't access @MainActor-isolated AppState. Same threading rationale as above.
    nonisolated(unsafe) private var isCurrentlyProcessing = false

    // Right Option key code
    private let rightOptionKeyCode: CGKeyCode = 61

    private init() {}

    // MARK: - Public API

    func startListening() {
        guard eventTap == nil else { return }

        PushLogger.log("HotkeyManager: startListening called")

        // Set up callbacks
        onKeyDown = { [weak self] in
            self?.handleKeyDown()
        }
        onKeyUp = { [weak self] in
            self?.handleKeyUp()
        }

        // Set up wake word listener callback
        WakeWordListener.shared.onWakeWordDetected = { [weak self] in
            Task { @MainActor in
                self?.handleWakeWordDetected()
            }
        }

        // Set up VAD callback for auto-stop
        AudioRecorder.shared.onSilenceDetected = { [weak self] in
            Task { @MainActor in
                self?.handleVADStop()
            }
        }

        // Start wake word listener if enabled
        if AppState.shared.wakeWordEnabled {
            WakeWordListener.shared.startListening()
        }

        // Try to create event tap - if it fails, we don't have permission
        attemptToCreateEventTap()
    }

    func stopListening() {
        retryTimer?.invalidate()
        retryTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isRightOptionPressed = false
        PushLogger.log("HotkeyManager: Stopped listening")
    }

    // MARK: - Private

    private func attemptToCreateEventTap() {
        PushLogger.log("HotkeyManager: attemptToCreateEventTap called")
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                // The system disables the tap on timeout or heavy input; if we don't
                // re-enable it the hotkey silently goes dead.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    // Synchronously, not via `Task { @MainActor }`: the tap gets
                    // disabled precisely because the main thread is busy, so
                    // queueing the recovery behind that same thread delays it for
                    // as long as the stall lasts — measured at 9 seconds once.
                    // This callback is serviced by the main run loop, so we are
                    // already on the main actor.
                    MainActor.assumeIsolated { manager.reEnableTap() }
                    return Unmanaged.passUnretained(event)
                }

                // Consume Escape key during recording or processing so full-screen apps (Safari, etc.)
                // don't also exit full-screen when the user presses Escape to cancel.
                if type == .keyDown,
                   event.getIntegerValueField(.keyboardEventKeycode) == 53,
                   (manager.isCurrentlyRecording || manager.isCurrentlyProcessing) {
                    Task { @MainActor in
                        manager.handleCancelRecording()
                    }
                    return nil  // Swallow the event
                }

                Task { @MainActor in
                    manager.handleEvent(event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        )

        // If tap is nil, either we lack permission, or we HAVE permission but the
        // tap still won't form — the classic state after a Sparkle auto-update
        // relaunch, where macOS doesn't re-establish the event tap for the
        // relaunched process. A clean relaunch fixes it (same as a manual reopen).
        guard let tap = tap else {
            if AXIsProcessTrusted() {
                PushLogger.log("HotkeyManager: accessibility trusted but tapCreate failed — likely post-update relaunch; attempting one-time clean relaunch")
                relaunchCleanlyOnce()
            } else {
                PushLogger.log("HotkeyManager: Failed to create event tap - requesting accessibility permission")
                requestAccessibilityAndRetry()
            }
            return
        }

        // Success! We have permission
        PushLogger.log("HotkeyManager: ✅ Event tap created successfully!")
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            // Clear any prior auto-relaunch marker now that the tap is healthy.
            UserDefaults.standard.removeObject(forKey: Self.autoRelaunchKey)
            let hotkeyName = AppState.shared.selectedHotkey.displayName
            PushLogger.log("HotkeyManager: ✅ Started listening for \(hotkeyName) key")
        }
    }

    // MARK: - Release watchdog

    /// Catch a hotkey release that never reached us.
    ///
    /// macOS disables an event tap whose callback doesn't return promptly, and
    /// the tap's run loop source lives on the main thread — so any main-thread
    /// stall long enough to trip that also swallows every event aimed at the tap,
    /// including the release that ends the dictation. The pill then sat there
    /// holding the transcript until the user pressed a second time to flush it.
    ///
    /// Rather than reason about which stalls can still happen, ask the hardware
    /// what the modifiers are actually doing. Two consecutive quiet ticks before
    /// acting, so a single odd reading can't cut a dictation short.
    private func startReleaseWatchdog() {
        stopReleaseWatchdog()
        let hotkey = AppState.shared.selectedHotkey
        // The generic modifier bit, not `flagMask`'s left/right-specific one:
        // `flagsState` is only documented to report the generic flags, and a
        // watchdog that misreads "released" would end every dictation instantly.
        let generic: CGEventFlags = hotkey.requiresAlternate ? .maskAlternate
            : hotkey.requiresCommand ? .maskCommand
            : .maskControl

        releaseMissTicks = 0
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRightOptionPressed else { return }
                guard !CGEventSource.flagsState(.combinedSessionState).contains(generic) else {
                    self.releaseMissTicks = 0
                    return
                }
                self.releaseMissTicks += 1
                guard self.releaseMissTicks >= 2 else { return }

                PushLogger.log("HotkeyManager: release was never delivered — ending dictation")
                self.isRightOptionPressed = false
                self.handleKeyUp()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseWatchdog = timer
    }

    private func stopReleaseWatchdog() {
        releaseWatchdog?.invalidate()
        releaseWatchdog = nil
        releaseMissTicks = 0
    }

    /// Re-enable the tap after the system disabled it (timeout / heavy input).
    private func reEnableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        PushLogger.log("HotkeyManager: re-enabled event tap after system disabled it")
    }

    // Marker timestamp so the recovery relaunch can never loop.
    private static let autoRelaunchKey = "hotkeyAutoRelaunchAt"

    /// Recover from the "trusted but tap won't create" state (typically right after
    /// a Sparkle update relaunch) by relaunching the app cleanly via a detached
    /// process — equivalent to the user quitting and reopening. Guarded so it runs
    /// at most once per 2-minute window; if a relaunch didn't help, fall back to the
    /// normal permission/retry path instead of relaunching forever.
    private func relaunchCleanlyOnce() {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: Self.autoRelaunchKey)
        guard now - last > 120 else {
            PushLogger.log("HotkeyManager: auto-relaunch skipped (one happened recently); falling back to retry")
            requestAccessibilityAndRetry()
            return
        }
        UserDefaults.standard.set(now, forKey: Self.autoRelaunchKey)
        PushLogger.log("HotkeyManager: relaunching to recover hotkey after update")

        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func requestAccessibilityAndRetry() {
        PushLogger.log("HotkeyManager: requestAccessibilityAndRetry called")
        // Request permission with prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        PushLogger.log("HotkeyManager: Requested accessibility permission, starting retry timer")

        // Retry every 2 seconds until we can create the event tap
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            PushLogger.log("HotkeyManager: Retrying event tap creation...")

            // Try to create the tap again
            let testEventMask = (1 << CGEventType.flagsChanged.rawValue) |
                                (1 << CGEventType.keyDown.rawValue)
            let testTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(testEventMask),
                callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                userInfo: nil
            )

            if testTap != nil {
                // Permission granted! Clean up test tap and do real setup
                PushLogger.log("HotkeyManager: ✅ Permission detected, setting up listener")
                timer.invalidate()

                DispatchQueue.main.async {
                    self.retryTimer = nil
                    self.attemptToCreateEventTap()
                }
            }
        }
    }

    private func handleEvent(_ event: CGEvent) {
        // Only process modifier key changes for hotkey detection
        guard event.type == .flagsChanged else { return }

        let flags = event.flags
        let rawFlags = flags.rawValue

        // Get the selected hotkey from AppState
        let hotkey = AppState.shared.selectedHotkey

        // Check if the selected hotkey is pressed
        let isHotkeyDown: Bool

        if hotkey.requiresAlternate {
            isHotkeyDown = flags.contains(.maskAlternate) && (rawFlags & hotkey.flagMask) != 0
        } else if hotkey.requiresCommand {
            isHotkeyDown = flags.contains(.maskCommand) && (rawFlags & hotkey.flagMask) != 0
        } else if hotkey.requiresControl {
            isHotkeyDown = flags.contains(.maskControl) && (rawFlags & hotkey.flagMask) != 0
        } else {
            isHotkeyDown = false
        }

        PushLogger.log("HotkeyManager: handleEvent - hotkey=\(hotkey.displayName), rawFlags=0x\(String(rawFlags, radix: 16)), isHotkeyDown=\(isHotkeyDown), currentlyPressed=\(isRightOptionPressed)")

        if isHotkeyDown && !isRightOptionPressed {
            isRightOptionPressed = true
            PushLogger.log("HotkeyManager: Detected \(hotkey.displayName) KEY DOWN")
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
        } else if !isHotkeyDown && isRightOptionPressed {
            isRightOptionPressed = false
            PushLogger.log("HotkeyManager: Detected \(hotkey.displayName) KEY UP")
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        }
    }

    private func handleKeyDown() {
        PushLogger.log("HotkeyManager: handleKeyDown called, hotkeyEnabled=\(AppState.shared.hotkeyEnabled), modelReady=\(AppState.shared.isModelReady)")
        guard AppState.shared.hotkeyEnabled else { return }
        // Recording does not need the model — only transcription does. Start
        // capturing immediately rather than silently swallowing the press
        // during startup; the engine finishes loading long before the user
        // stops talking, and the pipeline loads it on demand regardless.
        guard !AppState.shared.modelUnavailable else {
            PushLogger.log("HotkeyManager: No model available, ignoring hotkey")
            return
        }
        if !AppState.shared.isModelReady {
            PushLogger.log("HotkeyManager: Model still loading — recording ahead of it")
        }

        isCurrentlyRecording = true
        PressTiming.begin()
        startReleaseWatchdog()

        Task { @MainActor in
            PressTiming.mark("main-actor hop")
            AppState.shared.isListening = true
            AppState.shared.statusMessage = "Listening..."
            // Splits the gap that used to read as one 1072ms jump to "chirp":
            // everything the state change drags in (pill show + first SwiftUI
            // render) lands before this mark, the audio player's setup after it.
            PressTiming.mark("state set")

            // Play chirp sound if enabled
            if AppState.shared.playSoundOnStart {
                SoundPlayer.shared.playChirp()
                PressTiming.mark("chirp")
            }

            // Start audio recording
            await AudioRecorder.shared.startRecording()
        }

        let hotkeyName = AppState.shared.selectedHotkey.displayName
        PushLogger.log("HotkeyManager: \(hotkeyName) pressed - started listening")
    }

    private func handleKeyUp() {
        PushLogger.log("HotkeyManager: handleKeyUp called, hotkeyEnabled=\(AppState.shared.hotkeyEnabled)")
        stopReleaseWatchdog()
        guard AppState.shared.hotkeyEnabled else { return }

        isCurrentlyRecording = false
        isCurrentlyProcessing = true

        Task { @MainActor in
            AppState.shared.isListening = false
            AppState.shared.isProcessing = true
            AppState.shared.statusMessage = "Processing..."
            PushLogger.log("HotkeyManager: Set state to processing")

            // Stop recording and process
            let audioData = await AudioRecorder.shared.stopRecording()

            // Skip transcription if Silero VAD detected no speech — prevents
            // ambient noise and accidental key presses from producing random words.
            let hadSpeech = await SileroVAD.shared.speechWasDetected()
            if let data = audioData, hadSpeech {
                PushLogger.log("HotkeyManager: Sending to transcription pipeline")
                await TranscriptionPipeline.shared.process(audioData: data)
                PushLogger.log("HotkeyManager: Transcription complete")
            } else if !hadSpeech {
                PushLogger.log("HotkeyManager: No speech detected, skipping transcription")
            } else {
                PushLogger.log("HotkeyManager: No audio data to process")
            }

            isCurrentlyProcessing = false
            AppState.shared.isProcessing = false
            AppState.shared.statusMessage = "Ready"

            // Resume wake word listener if enabled
            if AppState.shared.wakeWordEnabled {
                WakeWordListener.shared.resumeListening()
            }
        }

        let hotkeyName = AppState.shared.selectedHotkey.displayName
        PushLogger.log("HotkeyManager: \(hotkeyName) released - processing")
    }

    // MARK: - Cancel Recording

    private func handleCancelRecording() {
        PushLogger.log("HotkeyManager: Cancelling recording/processing - discarding audio")
        stopReleaseWatchdog()

        isCurrentlyRecording = false
        isCurrentlyProcessing = false

        Task { @MainActor in
            // Stop recording and discard audio
            _ = await AudioRecorder.shared.stopRecording()

            // Reset state
            isRightOptionPressed = false
            AppState.shared.isListening = false
            AppState.shared.isProcessing = false
            AppState.shared.statusMessage = "Ready"

            // Resume wake word listener if enabled
            if AppState.shared.wakeWordEnabled {
                WakeWordListener.shared.resumeListening()
            }

            PushLogger.log("HotkeyManager: Recording cancelled")
        }
    }

    // MARK: - Wake Word Mode

    private func handleWakeWordDetected() {
        PushLogger.log("HotkeyManager: Wake word detected - starting recording with VAD")
        guard AppState.shared.isModelReady else {
            PushLogger.log("HotkeyManager: Model not ready yet, ignoring wake word")
            return
        }
        guard !AppState.shared.isListening, !AppState.shared.isProcessing else {
            PushLogger.log("HotkeyManager: Already listening or processing, ignoring wake word")
            return
        }

        // Pause wake word listener during recording
        WakeWordListener.shared.pauseListening()

        isCurrentlyRecording = true

        Task { @MainActor in
            AppState.shared.isListening = true
            AppState.shared.statusMessage = "Listening..."

            // Play chirp sound if enabled
            if AppState.shared.playSoundOnStart {
                SoundPlayer.shared.playChirp()
            }

            // Start audio recording WITH VAD enabled
            await AudioRecorder.shared.startRecording(withVAD: true)
        }

        PushLogger.log("HotkeyManager: Wake word activated - listening with VAD")
    }

    private func handleVADStop() {
        PushLogger.log("HotkeyManager: VAD triggered stop - processing")
        guard AppState.shared.isListening else {
            PushLogger.log("HotkeyManager: Not listening, ignoring VAD stop")
            return
        }

        isCurrentlyRecording = false
        isCurrentlyProcessing = true

        Task { @MainActor in
            AppState.shared.isListening = false
            AppState.shared.isProcessing = true
            AppState.shared.statusMessage = "Processing..."

            // Stop recording and process
            let audioData = await AudioRecorder.shared.stopRecording()
            PushLogger.log("HotkeyManager: VAD stop - Got audio data: \(audioData?.count ?? 0) bytes")

            if let data = audioData {
                PushLogger.log("HotkeyManager: Sending to transcription pipeline")
                await TranscriptionPipeline.shared.process(audioData: data)
                PushLogger.log("HotkeyManager: Transcription complete")
            } else {
                PushLogger.log("HotkeyManager: No audio data to process")
            }

            isCurrentlyProcessing = false
            AppState.shared.isProcessing = false
            AppState.shared.statusMessage = "Ready"

            // Resume wake word listener
            if AppState.shared.wakeWordEnabled {
                WakeWordListener.shared.resumeListening()
            }
        }

        PushLogger.log("HotkeyManager: VAD triggered stop - processing")
    }
}
