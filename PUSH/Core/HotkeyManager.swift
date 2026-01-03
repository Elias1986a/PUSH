import Foundation
import Carbon
import Cocoa

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

    // Right Option key code
    private let rightOptionKeyCode: CGKeyCode = 61

    private init() {}

    // MARK: - Public API

    func startListening() {
        guard eventTap == nil else { return }

        logToFile("HotkeyManager: startListening called")

        // Set up callbacks
        onKeyDown = { [weak self] in
            self?.handleKeyDown()
        }
        onKeyUp = { [weak self] in
            self?.handleKeyUp()
        }

        // Try to create event tap - if it fails, we don't have permission
        attemptToCreateEventTap()
    }

    private func logToFile(_ message: String) {
        let logPath = "/tmp/push_debug.log"
        let timestamp = Date().ISO8601Format()
        let logMessage = "\(timestamp): \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
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
        print("HotkeyManager: Stopped listening")
    }

    // MARK: - Private

    private func attemptToCreateEventTap() {
        logToFile("HotkeyManager: attemptToCreateEventTap called")
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        )

        // If tap is nil, we don't have permission
        guard let tap = tap else {
            logToFile("HotkeyManager: Failed to create event tap - requesting accessibility permission")
            print("HotkeyManager: Failed to create event tap - requesting accessibility permission")
            requestAccessibilityAndRetry()
            return
        }

        // Success! We have permission
        logToFile("HotkeyManager: ✅ Event tap created successfully!")
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            let hotkeyName = AppState.shared.selectedHotkey.displayName
            logToFile("HotkeyManager: ✅ Started listening for \(hotkeyName) key")
            print("HotkeyManager: ✅ Started listening for \(hotkeyName) key")
        }
    }

    private func requestAccessibilityAndRetry() {
        logToFile("HotkeyManager: requestAccessibilityAndRetry called")
        // Request permission with prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        logToFile("HotkeyManager: Requested accessibility permission, starting retry timer")

        // Retry every 2 seconds until we can create the event tap
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.logToFile("HotkeyManager: Retrying event tap creation...")
            print("HotkeyManager: Retrying event tap creation...")

            // Try to create the tap again
            let testEventMask = (1 << CGEventType.flagsChanged.rawValue)
            let testTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(testEventMask),
                callback: { _, _, event, _ in Unmanaged.passRetained(event) },
                userInfo: nil
            )

            if testTap != nil {
                // Permission granted! Clean up test tap and do real setup
                self.logToFile("HotkeyManager: ✅ Permission detected, setting up listener")
                print("HotkeyManager: ✅ Permission detected, setting up listener")
                timer.invalidate()

                DispatchQueue.main.async {
                    self.retryTimer = nil
                    self.attemptToCreateEventTap()
                }
            }
        }
    }

    private func handleEvent(_ event: CGEvent) {
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

        logToFile("HotkeyManager: handleEvent - hotkey=\(hotkey.displayName), rawFlags=0x\(String(rawFlags, radix: 16)), isHotkeyDown=\(isHotkeyDown), currentlyPressed=\(isRightOptionPressed)")

        if isHotkeyDown && !isRightOptionPressed {
            isRightOptionPressed = true
            logToFile("HotkeyManager: Detected \(hotkey.displayName) KEY DOWN")
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
        } else if !isHotkeyDown && isRightOptionPressed {
            isRightOptionPressed = false
            logToFile("HotkeyManager: Detected \(hotkey.displayName) KEY UP")
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        }
    }

    private func handleKeyDown() {
        logToFile("HotkeyManager: handleKeyDown called, hotkeyEnabled=\(AppState.shared.hotkeyEnabled)")
        guard AppState.shared.hotkeyEnabled else { return }

        Task {
            AppState.shared.isListening = true
            AppState.shared.statusMessage = "Listening..."

            // Start audio recording
            AudioRecorder.shared.startRecording()
        }

        let hotkeyName = AppState.shared.selectedHotkey.displayName
        logToFile("HotkeyManager: \(hotkeyName) pressed - started listening")
        print("HotkeyManager: \(hotkeyName) pressed - started listening")
    }

    private func handleKeyUp() {
        logToFile("HotkeyManager: handleKeyUp called, hotkeyEnabled=\(AppState.shared.hotkeyEnabled)")
        guard AppState.shared.hotkeyEnabled else { return }

        Task {
            AppState.shared.isListening = false
            AppState.shared.isProcessing = true
            AppState.shared.statusMessage = "Processing..."
            logToFile("HotkeyManager: Set state to processing")

            // Stop recording and process
            let audioData = AudioRecorder.shared.stopRecording()
            logToFile("HotkeyManager: Got audio data: \(audioData?.count ?? 0) bytes")

            if let data = audioData {
                logToFile("HotkeyManager: Sending to transcription pipeline")
                await TranscriptionPipeline.shared.process(audioData: data)
                logToFile("HotkeyManager: Transcription complete")
            } else {
                logToFile("HotkeyManager: No audio data to process")
            }

            AppState.shared.isProcessing = false
            AppState.shared.statusMessage = "Ready"
        }

        let hotkeyName = AppState.shared.selectedHotkey.displayName
        logToFile("HotkeyManager: \(hotkeyName) released - processing")
        print("HotkeyManager: \(hotkeyName) released - processing")
    }
}
