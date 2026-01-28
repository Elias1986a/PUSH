import Foundation
import Carbon
import Cocoa

/// Monitors global keystrokes to build typing context for autocomplete
@MainActor
final class KeystrokeMonitor: @unchecked Sendable {
    static let shared = KeystrokeMonitor()

    // MARK: - Configuration

    /// Max characters to keep in the context buffer
    private let maxContextLength = 500

    /// Delay after typing stops before triggering prediction
    private let predictionDelay: TimeInterval = 0.3

    // MARK: - State

    private(set) var contextBuffer = ""
    private(set) var isMonitoring = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var predictionTimer: Timer?

    // MARK: - Callbacks

    var onContextUpdated: ((String) -> Void)?
    var onPredictionTriggered: ((String) -> Void)?
    var onTabPressed: (() -> Void)?
    var onBacktickPressed: (() -> Void)?
    var onEscapePressed: (() -> Void)?

    private init() {}

    private func log(_ message: String) {
        let logPath = "/tmp/push_debug.log"
        let timestamp = Date().ISO8601Format()
        let logMessage = "\(timestamp): \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    /// Static log for use from C callbacks (nonisolated context)
    nonisolated static func writeLog(_ message: String) {
        let logPath = "/tmp/push_debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "\(timestamp): KeystrokeMonitor: \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    // MARK: - Public API

    func startMonitoring() {
        guard !isMonitoring else {
            log("KeystrokeMonitor: Already monitoring")
            return
        }

        log("KeystrokeMonitor: Starting...")

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                // Log directly from callback to verify it's being invoked
                KeystrokeMonitor.writeLog("CALLBACK FIRED! type=\(type.rawValue)")

                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleKeyEvent(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        )

        guard let tap = tap else {
            log("KeystrokeMonitor: ❌ Failed to create event tap (no accessibility permission?)")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isMonitoring = true
            log("KeystrokeMonitor: ✅ Started monitoring keystrokes")
        } else {
            log("KeystrokeMonitor: ❌ Failed to create run loop source")
        }
    }

    func stopMonitoring() {
        predictionTimer?.invalidate()
        predictionTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
        contextBuffer = ""
        print("KeystrokeMonitor: Stopped monitoring")
    }

    func clearContext() {
        contextBuffer = ""
    }

    // MARK: - Private

    private var keystrokeCount = 0

    // nonisolated because CGEvent callback runs off main thread
    nonisolated private func handleKeyEvent(_ event: CGEvent) {
        // Dispatch to main for all state access
        DispatchQueue.main.async { [self] in
            self.processKeyEvent(event)
        }
    }

    private func processKeyEvent(_ event: CGEvent) {
        keystrokeCount += 1
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Log every 10 keystrokes to avoid spam
        if keystrokeCount % 10 == 1 {
            log("KeystrokeMonitor: Received keystroke #\(keystrokeCount), keyCode=\(keyCode)")
        }

        // Handle special keys
        switch Int(keyCode) {
        case kVK_Delete: // Backspace
            if !contextBuffer.isEmpty {
                contextBuffer.removeLast()
            }
            schedulePrediction()
            return

        case kVK_Return, kVK_ANSI_KeypadEnter:
            contextBuffer.append("\n")
            schedulePrediction()
            return

        case kVK_Tab:
            // Tab accepts next word of prediction
            DispatchQueue.main.async { [weak self] in
                self?.onTabPressed?()
            }
            return

        case kVK_Escape:
            // Escape dismisses prediction
            DispatchQueue.main.async { [weak self] in
                self?.onEscapePressed?()
            }
            return

        case kVK_ANSI_Grave: // Backtick (`) accepts full prediction
            DispatchQueue.main.async { [weak self] in
                self?.onBacktickPressed?()
            }
            return

        case kVK_Space:
            contextBuffer.append(" ")
            schedulePrediction()
            return

        default:
            break
        }

        // Get the typed character
        let maxLength = 4
        var actualLength = 0
        var chars = [UniChar](repeating: 0, count: maxLength)
        event.keyboardGetUnicodeString(
            maxStringLength: maxLength,
            actualStringLength: &actualLength,
            unicodeString: &chars
        )

        if actualLength > 0 {
            let typed = String(utf16CodeUnits: chars, count: actualLength)

            // Skip control characters
            guard typed.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
                return
            }

            contextBuffer.append(typed)

            // Trim buffer if too long
            if contextBuffer.count > maxContextLength {
                let excess = contextBuffer.count - maxContextLength
                contextBuffer.removeFirst(excess)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onContextUpdated?(self.contextBuffer)
            }

            schedulePrediction()
        }
    }

    private func schedulePrediction() {
        predictionTimer?.invalidate()
        let context = contextBuffer
        predictionTimer = Timer.scheduledTimer(withTimeInterval: predictionDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard !context.isEmpty else { return }
            self.log("KeystrokeMonitor: Triggering prediction for context: '\(context.suffix(50))'")
            DispatchQueue.main.async {
                self.onPredictionTriggered?(context)
            }
        }
    }
}
