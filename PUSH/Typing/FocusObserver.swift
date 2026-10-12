import AppKit
import ApplicationServices

/// Tells Type when focus moves inside the frontmost app — Tab to the next
/// field, a sheet opening, a window closing — so the field icon follows focus
/// the whole time a field is eligible, not only after a key or click
/// (Cotypist shows it as soon as a field it serves has focus; Cotabby polls
/// focus every 50 ms). Accessibility notifications instead of polling.
@MainActor
final class FocusObserver {
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// Watches `app` (the frontmost one) from now on, and stops watching the last.
    func observe(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != observedPID else { return }
        stop()
        let pid = app.processIdentifier
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let me = Unmanaged<FocusObserver>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { me.onChange() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        // A busy app must not stall the main thread for long.
        AXUIElementSetMessagingTimeout(element, 0.1)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(created, element, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
    }
}
