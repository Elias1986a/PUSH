import AppKit
import ApplicationServices
import PUSHCore

/// Where the user is typing, read through Accessibility. Never logged.
struct FocusSnapshot: Sendable, Equatable {
    var pid: pid_t
    var bundleID: String?
    var appName: String?
    var windowTitle: String?
    var placeholder: String?
    var url: String?
    /// Text before and after the caret, when the field's value is readable.
    var before: String?
    var after: String?
    /// The caret in AppKit screen coordinates (bottom-left origin), when known.
    var caretRect: CGRect?
    /// The focused element's frame, AppKit coordinates — for the mirror card.
    var fieldFrame: CGRect?
    var isSecure: Bool
    /// Identifies the focused element, to tell a stale result from a fresh one.
    var elementID: Int
}

/// Reads the focused text field. Runs **off the main thread**: an
/// Accessibility call to a busy app can stall, and a stalled main thread makes
/// macOS disable PUSH's dictation event tap. Every call has a short timeout.
enum FocusReader {
    static let beforeWindow = 1_500
    static let afterWindow = 200
    private static let timeout: Float = 0.08

    nonisolated static func read() -> FocusSnapshot? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        guard let app: AXUIElement = attribute(system, kAXFocusedApplicationAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(app, timeout)
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        let running = NSRunningApplication(processIdentifier: pid)
        let bundleID = running?.bundleIdentifier
        AccessibilityEnabler.enableIfNeeded(app: app, pid: pid, bundleID: bundleID)

        guard let element: AXUIElement = attribute(app, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        let role: String? = attribute(element, kAXRoleAttribute)
        let subrole: String? = attribute(element, kAXSubroleAttribute)
        let isSecure = subrole == (kAXSecureTextFieldSubrole as String) || role == "AXSecureTextField"

        var snapshot = FocusSnapshot(
            pid: pid, bundleID: bundleID, appName: running?.localizedName,
            windowTitle: (attribute(app, kAXFocusedWindowAttribute) as AXUIElement?).flatMap { attribute($0, kAXTitleAttribute) },
            placeholder: attribute(element, kAXPlaceholderValueAttribute),
            url: nil, before: nil, after: nil, caretRect: nil, fieldFrame: frame(of: element),
            isSecure: isSecure, elementID: Int(CFHash(element)))
        // A password field: nothing more is read from it, ever.
        guard !isSecure else { return snapshot }

        snapshot.url = webURL(from: element)
        if let value: String = attribute(element, kAXValueAttribute),
           let range = selectedRange(element) {
            let text = value as NSString
            let caret = min(range.location, text.length)
            let end = min(caret + range.length, text.length)
            snapshot.before = lastCharacters(text.substring(to: caret), beforeWindow)
            snapshot.after = String(text.substring(from: end).prefix(afterWindow))
            snapshot.caretRect = caretRect(element, at: caret, length: text.length)
        }
        return snapshot
    }

    // MARK: - Pieces

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value: AXValue = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    /// The caret's position, from `kAXBoundsForRangeParameterizedAttribute`.
    /// The character before the caret is measured and its right edge used:
    /// an empty range is the unreliable case (TextEdit puts it a line too
    /// high). The empty range is the fallback, for a caret at the very start.
    private static func caretRect(_ element: AXUIElement, at caret: Int, length: Int) -> CGRect? {
        if caret > 0, let rect = bounds(element, CFRange(location: caret - 1, length: 1)), rect.height > 0,
           rect.width < 200 {   // a newline before the caret measures as a whole line
            return flipped(CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height))
        }
        if let rect = bounds(element, CFRange(location: caret, length: 0)), rect.height > 0 {
            return flipped(rect)
        }
        return nil
    }

    private static func bounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var range = range
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let p: AXValue = attribute(element, kAXPositionAttribute),
              let s: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return flipped(CGRect(origin: point, size: size))
    }

    /// Accessibility uses a top-left origin on the primary display; AppKit a
    /// bottom-left one.
    private static func flipped(_ rect: CGRect) -> CGRect {
        // CoreGraphics, not NSScreen: this runs off the main thread.
        let height = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The page's address, from the nearest web area above the field.
    private static func webURL(from element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for _ in 0..<30 {
            guard let node = current else { return nil }
            if (attribute(node, kAXRoleAttribute) as String?) == "AXWebArea" {
                if let url: URL = attribute(node, kAXURLAttribute) { return url.absoluteString }
                if let url: String = attribute(node, kAXURLAttribute) { return url }
            }
            current = attribute(node, kAXParentAttribute)
        }
        return nil
    }

    private static func lastCharacters(_ text: String, _ n: Int) -> String {
        text.count > n ? String(text.suffix(n)) : text
    }
}

/// Electron and Chromium build their Accessibility tree only when asked.
/// Electron's documented switch is `AXManualAccessibility`; Chromium browsers
/// answer `AXEnhancedUserInterface`. Set once per process.
enum AccessibilityEnabler {
    nonisolated(unsafe) private static var done: Set<pid_t> = []
    private static let lock = NSLock()

    private static let chromium = ["com.google.chrome", "com.brave.browser", "com.microsoft.edgemac",
                                   "company.thebrowser.browser", "company.thebrowser.dia", "com.vivaldi.vivaldi"]

    nonisolated static func enableIfNeeded(app: AXUIElement, pid: pid_t, bundleID: String?) {
        let first = lock.withLock { done.insert(pid).inserted }
        guard first else { return }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // Only browsers: on other apps this attribute can disturb window animations.
        if let id = bundleID?.lowercased(), chromium.contains(where: { id.hasPrefix($0) }) {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }
}
