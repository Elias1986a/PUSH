import Foundation
import AppKit

/// Injects text into the currently focused text field via clipboard paste
/// (the most compatible path across native apps, Electron, and web inputs)
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
