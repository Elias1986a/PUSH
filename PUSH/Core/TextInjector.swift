import Foundation
import AppKit
import PUSHCore

/// Injects text into the currently focused text field via clipboard paste
/// (the most compatible path across native apps, Electron, and web inputs)
@MainActor
final class TextInjector: @unchecked Sendable {
    static let shared = TextInjector()

    private init() {}

    /// The user's clipboard, captured before we overwrite it. Held as plain
    /// flavor->bytes maps rather than `NSPasteboardItem`s so the snapshot can
    /// cross between the background queue and the main actor: `Data` and
    /// `String` are `Sendable`, `NSPasteboardItem` is not.
    private struct Snapshot {
        let items: [[String: Data]]
        let changeCount: Int
    }

    private var snapshot: Snapshot?
    private static let snapshotQueue = DispatchQueue(label: "push.textinjector.clipboard")

    // MARK: - Public API

    /// Capture the user's clipboard ahead of time, off the main thread.
    ///
    /// Reading a pasteboard item's flavors is a synchronous cross-process call:
    /// macOS pasteboards are lazy, so `data(forType:)` asks the *owning app* to
    /// render that flavor on demand. Apps that advertise many rich flavors
    /// (Outlook, Word, Excel) — and endpoint DLP agents that scan every
    /// clipboard access — can stretch that into whole seconds.
    ///
    /// Done at inject time it lands squarely in the latency the user feels
    /// between finishing a sentence and seeing text. Done here it runs while
    /// they are still speaking, where there is time to spare, and off the main
    /// thread so a stall can't cost us the CGEvent tap.
    func prepareClipboardSnapshot() {
        let changeCount = NSPasteboard.general.changeCount
        snapshot = nil

        Self.snapshotQueue.async {
            let items = Self.copyItems(from: NSPasteboard.general)
            Task { @MainActor in
                // Discard it if anything landed on the clipboard while we read.
                guard NSPasteboard.general.changeCount == changeCount else { return }
                self.snapshot = Snapshot(items: items, changeCount: changeCount)
            }
        }
    }

    /// Insert text at the current cursor position in any app
    func insertText(_ text: String) {
        PushLogger.log("TextInjector: Inserting text via clipboard paste (\(text.count) chars)")
        insertViaClipboard(text)
        PushLogger.log("TextInjector: ✅ Inserted via clipboard paste")
    }

    // MARK: - Private Methods

    /// Deep-copy every flavor of every item currently on the pasteboard.
    /// Expensive by nature — see `prepareClipboardSnapshot()`.
    nonisolated private static func copyItems(from pasteboard: NSPasteboard) -> [[String: Data]] {
        pasteboard.pasteboardItems?.map { item in
            var flavors: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    flavors[type.rawValue] = data
                }
            }
            return flavors
        } ?? []
    }

    /// Rebuild pasteboard items from a snapshot. Cheap — the bytes are already
    /// in memory, so this touches no other process.
    private static func pasteboardItems(from flavorSets: [[String: Data]]) -> [NSPasteboardItem] {
        flavorSets.compactMap { flavors in
            guard !flavors.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in flavors {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
    }

    private func insertViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Prefer the snapshot taken when recording started. Fall back to reading
        // the clipboard now only if it moved mid-dictation (the user copied
        // something while speaking) or the snapshot hasn't landed yet.
        let savedFlavorSets: [[String: Data]]
        if let snapshot, snapshot.changeCount == pasteboard.changeCount {
            savedFlavorSets = snapshot.items
        } else {
            PushLogger.log("TextInjector: no usable clipboard snapshot — copying inline")
            savedFlavorSets = Self.copyItems(from: pasteboard)
        }
        snapshot = nil
        let savedItems = Self.pasteboardItems(from: savedFlavorSets)
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
