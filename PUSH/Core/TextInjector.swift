import Foundation
import AppKit
import ApplicationServices

/// Injects text into the currently focused text field using Accessibility API
@MainActor
final class TextInjector: @unchecked Sendable {
    static let shared = TextInjector()

    private init() {}

    // MARK: - Public API

    /// Insert text at the current cursor position in any app
    func insertText(_ text: String) {
        PushLogger.log("TextInjector: Attempting to insert text (\(text.count) chars)")

        // Try accessibility API first (doesn't touch clipboard)
        if insertViaAccessibility(text) {
            PushLogger.log("TextInjector: ✅ Inserted via accessibility API")
            return
        }

        // Fall back to clipboard + paste (works in all apps)
        PushLogger.log("TextInjector: Accessibility failed, falling back to clipboard paste")
        insertViaClipboard(text)
        PushLogger.log("TextInjector: ✅ Inserted via clipboard paste")
    }

    // MARK: - Private Methods

    private func insertViaAccessibility(_ text: String) -> Bool {
        // Get the focused element
        guard let focusedElement = getFocusedElement() else {
            PushLogger.log("TextInjector: No focused element found")
            return false
        }

        // Check if the element supports text insertion
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(focusedElement, kAXValueAttribute as CFString, &settable)

        guard result == .success && settable.boolValue else {
            PushLogger.log("TextInjector: Element value not settable")
            return false
        }

        // Get current value
        var currentValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &currentValue)

        // Get placeholder value to avoid treating it as real content
        var placeholderValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXPlaceholderValueAttribute as CFString, &placeholderValue)
        let placeholder = placeholderValue as? String

        // If the current value matches the placeholder, the field is actually empty
        let effectiveValue: String? = {
            guard let current = currentValue as? String else { return nil }
            if let placeholder = placeholder, current == placeholder { return "" }
            return current
        }()

        // Get selected text range to know where to insert
        var selectedRange: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        if let range = selectedRange,
           let axValue = range as! AXValue?,
           let currentText = effectiveValue {
            var cfRange = CFRange()
            if AXValueGetValue(axValue, .cfRange, &cfRange) {
                // Insert at selection
                let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
                let newText = (currentText as NSString).replacingCharacters(in: nsRange, with: text)

                let setResult = AXUIElementSetAttributeValue(
                    focusedElement,
                    kAXValueAttribute as CFString,
                    newText as CFTypeRef
                )

                if setResult == .success {
                    // Move cursor to end of inserted text
                    let newCursorPosition = cfRange.location + text.count
                    setSelectedRange(focusedElement, location: newCursorPosition, length: 0)
                    return true
                }
            }
        }

        // If we can't get the selection, just append
        let newText = (effectiveValue ?? "") + text
        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )

        return setResult == .success
    }

    private func insertViaClipboard(_ text: String) {
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let savedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.compactMap { item in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        } ?? []
        let originalChangeCount = pasteboard.changeCount

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let injectedChangeCount = pasteboard.changeCount

        // Wait a bit for clipboard to sync, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()
        }

        // Restore clipboard after a longer delay (1s to let slow apps finish pasting)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Only restore if user hasn't modified the clipboard since we injected.
            guard pasteboard.changeCount == injectedChangeCount else { return }
            guard !savedItems.isEmpty else {
                if pasteboard.changeCount == injectedChangeCount && originalChangeCount == injectedChangeCount {
                    pasteboard.clearContents()
                }
                return
            }
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }
    }

    private func getFocusedElement() -> AXUIElement? {
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Get the focused UI element
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success else {
            return nil
        }

        let typeID = CFGetTypeID(focusedElement as CFTypeRef)
        guard typeID == AXUIElementGetTypeID() else {
            return nil
        }
        return (focusedElement as! AXUIElement)
    }

    private func setSelectedRange(_ element: AXUIElement, location: Int, length: Int) {
        var range = CFRange(location: location, length: length)
        if let axValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                axValue
            )
        }
    }

    private func simulatePaste() {
        // Create Cmd+V key event
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) { // V key
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
