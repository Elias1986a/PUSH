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
    /// The focused element is somewhere text is typed (not a menu item, list
    /// row or button that happens to hold the focus).
    var isTextInput: Bool
    var role: String?
    /// What the field says about itself (title, description, placeholder) and
    /// its web id — for spotting sign-in and verification fields.
    var labels: [String?]
    var domIdentifier: String?
    /// Identifies the focused element, to tell a stale result from a fresh one.
    var elementID: Int
    /// The field is part of a web page (in or under an `AXWebArea`), not the
    /// app's own controls — in a browser, not the address bar.
    var insideWebPage = false
    /// The font of the text at the caret, when the app reports it.
    var font: FieldFont? = nil
    /// In a terminal: where the last visible character before the cursor is
    /// (AppKit coordinates). Claude Code draws its own block cursor and leaves
    /// Terminal's real one on it, a cell or more past it, or at the start of
    /// the row under its prompt — so the end of the typed text is what says
    /// where its caret is.
    var textEndRect: CGRect? = nil
}

/// A font as an app reports it: the suggestion is drawn in it, so it reads as
/// the next words of the same text (Cotypist matches the field's font too).
struct FieldFont: Sendable, Equatable {
    var name: String
    var size: CGFloat
}

/// Reads the focused text field. Runs **off the main thread**: an
/// Accessibility call to a busy app can stall, and a stalled main thread makes
/// macOS disable PUSH's dictation event tap. Every call has a short timeout.
enum FocusReader {
    /// Up to this much text before the caret (Cotabby sends up to 14,000; its
    /// recall eval found facts far back invisible with less). The start moves
    /// in steps (`PromptWindow`) so the KV cache keeps matching.
    static let beforeWindow = 4_000
    static let afterWindow = 200
    private static let timeout: Float = 0.08

    nonisolated static func read() -> FocusSnapshot? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        // Webex (Qt) in front makes the system-wide element fail with
        // cannotComplete, while Webex itself answers for its focused field:
        // ask the frontmost app directly then.
        guard let app: AXUIElement = attribute(system, kAXFocusedApplicationAttribute)
                ?? NSWorkspace.shared.frontmostApplication.map({ AXUIElementCreateApplication($0.processIdentifier) })
        else { return nil }
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
            isSecure: isSecure, isTextInput: Self.textRoles.contains(role ?? ""),
            role: role,
            labels: [attribute(element, kAXTitleAttribute), attribute(element, kAXDescriptionAttribute),
                     attribute(element, kAXPlaceholderValueAttribute)],
            domIdentifier: attribute(element, "AXDOMIdentifier"),
            elementID: Int(CFHash(element)))
        // A password field: nothing more is read from it, ever.
        guard !isSecure else { return snapshot }

        let page = webArea(from: element)
        snapshot.url = page.url
        snapshot.insideWebPage = page.found
        if let value: String = attribute(element, kAXValueAttribute),
           let range = selectedRange(element) {
            let text = value as NSString
            let caret = min(range.location, text.length)
            let end = min(caret + range.length, text.length)
            let start = PromptWindow.start(length: caret, maximum: beforeWindow)
            snapshot.before = text.substring(with: NSRange(location: start, length: caret - start))
            snapshot.after = String(text.substring(from: end).prefix(afterWindow))
            // WebKit's caret box first: its character bounds run 2 pt past
            // the glyph (Safari's text areas put a suggestion a space too far
            // right). Chrome answers it with an empty box, so its character
            // bounds are used — and its rich-text boxes have a value but no
            // range bounds, where only the text markers know the caret.
            snapshot.caretRect = markerCaret(element)
                ?? caretRect(element, at: caret, in: text)
                ?? textMarkerRead(element)?.caret
            if SurfaceClass.classify(bundleID: bundleID) == .terminal {
                snapshot.textEndRect = textEndRect(element, before: caret, in: text)
            }
            if caret > 0 { snapshot.font = font(element, at: caret - 1) }
        } else if let marked = textMarkerRead(element) {
            // Web views (Mail's body, many browser editors) have no plain value.
            snapshot.before = marked.before
            snapshot.caretRect = marked.caret
            snapshot.font = marked.font
        }
        return snapshot
    }

    /// PUSH's own focused text view, read directly: Accessibility asked about
    /// its own process came back empty. Only for the onboarding try-it box.
    @MainActor
    static func readOwn() -> FocusSnapshot? {
        guard NSApp.isActive, let window = NSApp.keyWindow,
              let view = window.firstResponder as? NSTextView, view.isEditable else { return nil }
        let text = view.string as NSString
        let selection = view.selectedRange()
        let caret = min(selection.location, text.length)
        let end = min(caret + selection.length, text.length)
        let start = PromptWindow.start(length: caret, maximum: beforeWindow)
        let caretRect = view.firstRect(forCharacterRange: NSRange(location: caret, length: 0), actualRange: nil)
        let box = view.enclosingScrollView ?? view
        let fieldFrame = window.convertToScreen(box.convert(box.bounds, to: nil))
        return FocusSnapshot(
            pid: ProcessInfo.processInfo.processIdentifier, bundleID: Bundle.main.bundleIdentifier,
            appName: "PUSH", windowTitle: nil, placeholder: nil, url: nil,
            before: text.substring(with: NSRange(location: start, length: caret - start)),
            after: String(text.substring(from: end).prefix(afterWindow)),
            caretRect: caretRect.height > 0 ? CGRect(x: caretRect.minX, y: caretRect.minY, width: 0, height: caretRect.height) : nil,
            fieldFrame: fieldFrame, isSecure: false, isTextInput: true, role: "AXTextArea",
            labels: [], domIdentifier: nil, elementID: ObjectIdentifier(view).hashValue,
            font: (view.font ?? view.typingAttributes[.font] as? NSFont).map { FieldFont(name: $0.fontName, size: $0.pointSize) })
    }

    /// WebKit's text-marker attributes: the text from the start of the editable
    /// area to the caret, the caret's position and the font before it.
    ///
    /// Mail's compose body answers no `AXStartTextMarkerForTextMarkerRange`,
    /// so the caret's marker comes from `AXTextMarkerRangeCopyStartMarker`
    /// there. Without it nothing before the caret was read: the font was
    /// guessed from the caret's height (smaller than Mail's Helvetica 12) and
    /// the text was only what PUSH saw typed (bug pass, 2026-10-12).
    private static func textMarkerRead(_ element: AXUIElement) -> (before: String?, caret: CGRect?, font: FieldFont?)? {
        guard let selection: CFTypeRef = attribute(element, "AXSelectedTextMarkerRange") else { return nil }
        let caret = caretBox(element, selection)
        var before: String?
        var font: FieldFont?
        if let caretMarker = startMarker(element, of: selection) {
            if let start: CFTypeRef = attribute(element, "AXStartTextMarker"),
               let range: CFTypeRef = parameterized(element, "AXTextMarkerRangeForUnorderedTextMarkers",
                                                    [start, caretMarker] as CFArray),
               let text: String = parameterized(element, "AXStringForTextMarkerRange", range) {
                let ns = text as NSString
                let start = PromptWindow.start(length: ns.length, maximum: beforeWindow)
                before = ns.substring(from: start)
            }
            // The field's font is the character before the caret's.
            if let previous: CFTypeRef = parameterized(element, "AXPreviousTextMarkerForTextMarker", caretMarker),
               let range: CFTypeRef = parameterized(element, "AXTextMarkerRangeForUnorderedTextMarkers",
                                                    [previous, caretMarker] as CFArray),
               let text: NSAttributedString = parameterized(element, "AXAttributedStringForTextMarkerRange", range) {
                font = fieldFont(in: text)
            }
        }
        return before == nil && caret == nil ? nil : (before, caret, font)
    }

    /// WebKit's caret box starts at the insertion point and is 2 pt wide; its
    /// left edge is where typed text ends. (The character before is no guide:
    /// Mail measures Helvetica's "I" 6 pt wide, so a suggestion after it
    /// started a space too far right — "I 'm".)
    private static func caretBox(_ element: AXUIElement, _ selection: CFTypeRef) -> CGRect? {
        markerBounds(element, selection).map { CGRect(x: $0.minX, y: $0.minY, width: 0, height: $0.height) }
    }

    private static func markerCaret(_ element: AXUIElement) -> CGRect? {
        guard let selection: CFTypeRef = attribute(element, "AXSelectedTextMarkerRange") else { return nil }
        return caretBox(element, selection)
    }

    /// The marker a range starts at: WebKit's attribute, or the system's own
    /// call for apps that do not answer it.
    private static func startMarker(_ element: AXUIElement, of range: CFTypeRef) -> CFTypeRef? {
        if let marker: CFTypeRef = parameterized(element, "AXStartTextMarkerForTextMarkerRange", range) { return marker }
        guard CFGetTypeID(range) == AXTextMarkerRangeGetTypeID() else { return nil }
        return AXTextMarkerRangeCopyStartMarker(unsafeBitCast(range, to: AXTextMarkerRange.self))
    }

    private static func markerBounds(_ element: AXUIElement, _ range: CFTypeRef) -> CGRect? {
        parameterized(element, "AXBoundsForTextMarkerRange", range).flatMap { (value: AXValue) in
            var rect = CGRect.zero
            return AXValueGetValue(value, .cgRect, &rect) && rect.height > 0 ? flipped(rect) : nil
        }
    }

    private static func parameterized<T>(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success,
              let value else { return nil }
        return value as? T
    }

    /// Roles text is typed into. A web area counts: Mail's body and other
    /// web editors are one.
    static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXWebArea"]

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
    /// high). After a line break that edge belongs to the line above — in
    /// Terminal every row ends in one, so a caret just wrapped to a new row
    /// was placed at the right edge of the old one — so the character at the
    /// caret is measured instead and its left edge used. The empty range is
    /// the last resort, for a caret at the very end.
    private static func isBreak(_ index: Int, in text: NSString) -> Bool {
        index >= 0 && index < text.length
            && CharacterSet.newlines.contains(UnicodeScalar(text.character(at: index)) ?? " ")
    }

    /// See `FocusSnapshot.textEndRect`. Looks back at most one row's worth.
    private static func textEndRect(_ element: AXUIElement, before caret: Int, in text: NSString) -> CGRect? {
        guard caret > 0 else { return nil }
        var index = caret - 1
        let limit = max(0, caret - 400)
        while index >= limit, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(text.character(at: index)) ?? " ") {
            index -= 1
        }
        guard index >= limit, let rect = bounds(element, CFRange(location: index, length: 1)),
              rect.height > 0, rect.width < 200 else { return nil }
        return flipped(rect)
    }

    private static func caretRect(_ element: AXUIElement, at caret: Int, in text: NSString) -> CGRect? {
        func isBreak(_ index: Int) -> Bool { Self.isBreak(index, in: text) }
        if caret > 0, !isBreak(caret - 1), let rect = bounds(element, CFRange(location: caret - 1, length: 1)),
           rect.height > 0, rect.width < 200 {   // some apps measure a character as a whole line
            return flipped(CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height))
        }
        if caret < text.length, !isBreak(caret), let rect = bounds(element, CFRange(location: caret, length: 1)),
           rect.height > 0, rect.width < 200 {
            return flipped(CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height))
        }
        if let rect = bounds(element, CFRange(location: caret, length: 0)), rect.height > 0 {
            return flipped(rect)
        }
        return nil
    }

    /// The `AXFont` of the character at `location`.
    private static func font(_ element: AXUIElement, at location: Int) -> FieldFont? {
        var range = CFRange(location: location, length: 1)
        guard let axRange = AXValueCreate(.cfRange, &range),
              let text: NSAttributedString = parameterized(
                element, kAXAttributedStringForRangeParameterizedAttribute as String, axRange),
              text.length > 0 else { return nil }
        return fieldFont(in: text)
    }

    /// The font an Accessibility attributed string reports for its first
    /// character. Chrome's rich-text boxes give only a size; the name is then
    /// empty and the system font is drawn at that size.
    private static func fieldFont(in text: NSAttributedString) -> FieldFont? {
        guard text.length > 0,
              let font = text.attribute(NSAttributedString.Key("AXFont"), at: 0,
                                        effectiveRange: nil) as? [String: Any],
              let size = (font["AXFontSize"] as? NSNumber)?.doubleValue, size > 0 else { return nil }
        let name = font["AXFontName"] as? String ?? font["AXFontFamily"] as? String ?? ""
        return FieldFont(name: name, size: CGFloat(size))
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

    /// The nearest web area at or above the field, and the page's address.
    private static func webArea(from element: AXUIElement) -> (found: Bool, url: String?) {
        var current: AXUIElement? = element
        for _ in 0..<30 {
            guard let node = current else { break }
            if (attribute(node, kAXRoleAttribute) as String?) == "AXWebArea" {
                if let url: URL = attribute(node, kAXURLAttribute) { return (true, url.absoluteString) }
                return (true, attribute(node, kAXURLAttribute))
            }
            current = attribute(node, kAXParentAttribute)
        }
        return (false, nil)
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
