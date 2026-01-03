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
        log("TextInjector: Attempting to insert: '\(text)'")

        // Use clipboard + paste as primary method (works in all apps)
        insertViaClipboard(text)
        log("TextInjector: ✅ Inserted via clipboard paste")
        print("TextInjector: Inserted via clipboard paste")
    }

    private func log(_ message: String) {
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

    // MARK: - Private Methods

    private func insertViaAccessibility(_ text: String) -> Bool {
        // Get the focused element
        guard let focusedElement = getFocusedElement() else {
            print("TextInjector: No focused element found")
            return false
        }

        // Check if the element supports text insertion
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(focusedElement, kAXValueAttribute as CFString, &settable)

        guard result == .success && settable.boolValue else {
            print("TextInjector: Element value not settable")
            return false
        }

        // Get current value
        var currentValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &currentValue)

        // Get selected text range to know where to insert
        var selectedRange: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        if let range = selectedRange,
           let axValue = range as! AXValue?,
           let currentText = currentValue as? String {
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
        let newText = (currentValue as? String ?? "") + text
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
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        }

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Wait a bit for clipboard to sync, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()
        }

        // Restore clipboard after a longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let savedItems = savedItems, !savedItems.isEmpty {
                pasteboard.clearContents()
                for (type, data) in savedItems {
                    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
            }
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
