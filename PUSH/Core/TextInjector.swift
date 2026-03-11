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
        PushLogger.log("TextInjector: Inserting text via clipboard paste (\(text.count) chars)")
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

        // Best approach: set kAXSelectedTextAttribute to replace current selection with our text.
        // This inserts at the cursor position without needing to read/manipulate the field's content,
        // which avoids issues with placeholder text being treated as real content.
        var selectedTextSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(focusedElement, kAXSelectedTextAttribute as CFString, &selectedTextSettable)

        if selectedTextSettable.boolValue {
            let setResult = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if setResult == .success {
                PushLogger.log("TextInjector: Inserted via kAXSelectedTextAttribute")
                return true
            }
            PushLogger.log("TextInjector: kAXSelectedTextAttribute settable but set failed (\(setResult.rawValue))")
        }

        // Fallback: set kAXValueAttribute directly (for simple text fields)
        var valueSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(focusedElement, kAXValueAttribute as CFString, &valueSettable)

        guard valueSettable.boolValue else {
            PushLogger.log("TextInjector: Neither selected text nor value is settable")
            return false
        }

        // When setting value directly, just set to our text (don't try to read and append,
        // as the "current value" may contain placeholder text from web inputs)
        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
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
