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

    // Right Option key code
    private let rightOptionKeyCode: CGKeyCode = 61

    private init() {}

    // MARK: - Public API

    func startListening() {
        guard eventTap == nil else { return }

        // We need accessibility permissions for this
        guard AXIsProcessTrusted() else {
            print("HotkeyManager: Accessibility permission required")
            return
        }

        // Set up callbacks
        onKeyDown = { [weak self] in
            self?.handleKeyDown()
        }
        onKeyUp = { [weak self] in
            self?.handleKeyUp()
        }

        // Create event tap for key events
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        // Store self reference for the callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
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
        ) else {
            print("HotkeyManager: Failed to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("HotkeyManager: Started listening for Right Option key")
        }
    }

    func stopListening() {
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

    private func handleEvent(_ event: CGEvent) {
        let flags = event.flags

        // Check if Right Option is pressed
        // Right Option sets both .maskAlternate and .maskNonCoalesced flags
        // We detect it by checking the raw flag value
        let rawFlags = flags.rawValue
        let rightOptionMask: UInt64 = 0x40  // Right option specific flag

        let isRightOptionDown = flags.contains(.maskAlternate) &&
                                (rawFlags & rightOptionMask) != 0

        if isRightOptionDown && !isRightOptionPressed {
            isRightOptionPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
        } else if !isRightOptionDown && isRightOptionPressed {
            isRightOptionPressed = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        }
    }

    private func handleKeyDown() {
        guard AppState.shared.hotkeyEnabled else { return }

        Task {
            AppState.shared.isListening = true
            AppState.shared.statusMessage = "Listening..."

            // Start audio recording
            AudioRecorder.shared.startRecording()
        }

        print("HotkeyManager: Right Option pressed - started listening")
    }

    private func handleKeyUp() {
        guard AppState.shared.hotkeyEnabled else { return }

        Task {
            AppState.shared.isListening = false
            AppState.shared.isProcessing = true
            AppState.shared.statusMessage = "Processing..."

            // Stop recording and process
            let audioData = AudioRecorder.shared.stopRecording()

            if let data = audioData {
                await TranscriptionPipeline.shared.process(audioData: data)
            }

            AppState.shared.isProcessing = false
            AppState.shared.statusMessage = "Ready"
        }

        print("HotkeyManager: Right Option released - processing")
    }
}
