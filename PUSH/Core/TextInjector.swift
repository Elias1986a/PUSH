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

    /// A copy that is still being read on the background queue. Kept so that a
    /// dictation shorter than the read can wait for the answer it already asked
    /// for, instead of starting a second copy of the same expensive work on the
    /// main thread while the user waits for their text.
    private final class PendingCopy: @unchecked Sendable {
        let changeCount: Int
        private let finished = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var items: [[String: Data]]?

        init(changeCount: Int) { self.changeCount = changeCount }

        func fulfill(_ items: [[String: Data]]) {
            lock.lock()
            self.items = items
            lock.unlock()
            finished.signal()
        }

        /// Blocks up to `timeout` for the read to land. Returns nil if it is
        /// still out — the caller then has to copy inline.
        func wait(timeout: TimeInterval) -> [[String: Data]]? {
            guard finished.wait(timeout: .now() + timeout) == .success else { return nil }
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    private var snapshot: Snapshot?
    private var pendingCopy: PendingCopy?
    private static let snapshotQueue = DispatchQueue(label: "push.textinjector.clipboard")

    /// How long injection will wait for an in-flight background copy before
    /// giving up and reading the pasteboard itself. Long enough for a normal
    /// read to land, short enough that it beats doing the read twice.
    private static let pendingCopyWait: TimeInterval = 0.35

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

        // Nothing has touched the clipboard since we last read it — including
        // the restore at the end of the previous dictation, which puts back
        // bytes we already hold. Re-reading here would ask Outlook to render
        // every flavor again for an answer we have.
        if let snapshot, snapshot.changeCount == changeCount { return }
        if let pendingCopy, pendingCopy.changeCount == changeCount { return }

        snapshot = nil
        let copy = PendingCopy(changeCount: changeCount)
        pendingCopy = copy

        Self.snapshotQueue.async {
            let items = Self.copyItems(from: NSPasteboard.general)
            copy.fulfill(items)
            Task { @MainActor in
                if self.pendingCopy === copy { self.pendingCopy = nil }
                // Discard it if anything landed on the clipboard while we read.
                guard NSPasteboard.general.changeCount == changeCount else { return }
                self.snapshot = Snapshot(items: items, changeCount: changeCount)
            }
        }
    }

    /// Insert text at the current cursor position in any app
    func insertText(_ text: String) {
        // Which app is about to receive the Cmd+V. The paste goes wherever the
        // system says is frontmost, so when text lands in the wrong window this
        // is the only line that says why — worth carrying permanently, since
        // "it pasted somewhere else" is otherwise unfalsifiable from a log.
        let target = NSWorkspace.shared.frontmostApplication
        PushLogger.log("TextInjector: frontmost app is \(target?.bundleIdentifier ?? target?.localizedName ?? "unknown"), PUSH isActive=\(NSApp.isActive), policy=\(NSApp.activationPolicy().rawValue)")
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
        } else if let pendingCopy, pendingCopy.changeCount == pasteboard.changeCount,
                  let items = pendingCopy.wait(timeout: Self.pendingCopyWait) {
            savedFlavorSets = items
        } else {
            // The slow path: a synchronous cross-process read, on the main
            // thread, inside the latency the user feels. Timed so a machine
            // that keeps landing here says so in the log.
            let start = DispatchTime.now()
            savedFlavorSets = Self.copyItems(from: pasteboard)
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000
            PushLogger.log("TextInjector: no usable clipboard snapshot — copied inline in \(String(format: "%.0f", ms))ms")
        }
        snapshot = nil
        pendingCopy = nil
        let savedItems = Self.pasteboardItems(from: savedFlavorSets)
        let originalChangeCount = pasteboard.changeCount

        // Set new text
        pasteboard.clearContents()
        pasteboard.writeObjects([Self.transcriptItem(text)])
        let injectedChangeCount = pasteboard.changeCount

        // Wait a bit for clipboard to sync, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()
        }

        // Restore clipboard after a longer delay (1s to let slow apps finish pasting)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            MainActor.assumeIsolated {
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

                // We wrote these bytes, so we already know what is on the
                // clipboard: keep them as the snapshot for the next dictation.
                // Without this, every dictation after the first found a moved
                // changeCount and paid for a full re-read of a rich clipboard.
                self.snapshot = Snapshot(items: savedFlavorSets, changeCount: pasteboard.changeCount)
            }
        }
    }

    /// The transcript, marked so clipboard managers leave it out of history.
    ///
    /// Without this, every sentence the user dictates lands permanently in
    /// Raycast/Maccy/Paste/Alfred/1Password — a full day's speech, including
    /// whatever they dictated into a password reset or a private message. The
    /// clipboard is a delivery mechanism here, not something the user copied.
    ///
    /// `org.nspasteboard.TransientType` and `AutoGeneratedType` are the
    /// nspasteboard.org convention (the de-facto standard those managers all
    /// implement): the flavors carry no data, their mere presence is the
    /// signal. A manager that doesn't recognise them simply ignores them, so
    /// this is safe on any Mac.
    ///
    /// `.string` is written first and is the only flavor with content, so
    /// Cmd+V behaves exactly as before.
    private static func transcriptItem(_ text: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for marker in transientMarkers {
            item.setString("", forType: marker)
        }
        return item
    }

    private static let transientMarkers: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    ]

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
