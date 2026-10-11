import AppKit
import ApplicationServices
import PUSHCore

/// The text in the focused window, through Accessibility: no screen capture,
/// no new permission, exact. Skips the field being typed in, password
/// fields, menus and toolbars. Bounded in nodes and time — a big web page can
/// hold tens of thousands of elements. Runs off the main thread. Never logged.
enum ScreenTextReader {
    private static let maximumNodes = 3_000
    private static let deadline: TimeInterval = 0.15
    private static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXHeading"]
    private static let skippedRoles: Set<String> = [
        "AXSecureTextField", "AXMenuBar", "AXMenu", "AXToolbar", "AXScrollBar", "AXImage", "AXButton",
        "AXPopUpButton", "AXMenuButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXProgressIndicator",
    ]
    private static let attributes = [kAXRoleAttribute, kAXValueAttribute, kAXTitleAttribute, kAXPositionAttribute,
                                     kAXSizeAttribute, kAXVisibleChildrenAttribute, kAXChildrenAttribute] as CFArray

    nonisolated static func read(pid: pid_t) -> [ScreenTextSelector.Item] {
        let app = AXUIElementCreateApplication(pid)
        guard let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute) else { return [] }
        let focused: AXUIElement? = attribute(app, kAXFocusedUIElementAttribute)
        let windowFrame = frame(window)
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let stop = Date().addingTimeInterval(deadline)
        var queue: [AXUIElement] = [window]
        var head = 0
        var items: [ScreenTextSelector.Item] = []
        while head < queue.count, head < maximumNodes, Date() < stop {
            let element = queue[head]
            head += 1
            if let focused, CFEqual(element, focused) { continue }
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 7 else { continue }
            let role = values[0] as? String ?? ""
            if skippedRoles.contains(role) { continue }
            if textRoles.contains(role) {
                let text = (values[1] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (values[2] as? String) ?? ""
                if !text.isEmpty, let rect = rect(position: values[3], size: values[4]), rect.width > 0,
                   windowFrame.map({ $0.intersects(rect) }) ?? true {
                    // Accessibility is top-left origin; the selector wants AppKit's.
                    let flipped = CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
                    items.append(.init(text: text, frame: flipped))
                }
                if role == "AXStaticText" { continue }
            }
            // Visible children where the element offers them (long lists and
            // tables hold thousands of rows off screen).
            let children = (values[5] as? [AXUIElement]) ?? (values[6] as? [AXUIElement]) ?? []
            queue.append(contentsOf: children)
        }
        return items
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        rect(position: attribute(element, kAXPositionAttribute) as AXValue? as AnyObject?,
             size: attribute(element, kAXSizeAttribute) as AXValue? as AnyObject?)
    }

    private static func rect(position: AnyObject?, size: AnyObject?) -> CGRect? {
        guard let position, let size, CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }
}
