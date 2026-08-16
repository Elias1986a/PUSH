import Foundation

/// SPIKE: does `NSUbiquitousKeyValueStore` work in PUSH?
///
/// PUSH cannot be sandboxed — global hotkeys and text injection forbid it —
/// and iCloud key-value storage is historically sandbox-mediated. Apple grants
/// the entitlement on a Developer ID profile (verified), but a granted
/// entitlement is not a working one. This answers that empirically, because
/// the alternative is a CloudKit private database: no login either, but far
/// more work than the ~kilobyte of settings and dictionary we actually sync.
///
/// Writes a stamp naming this machine, then reports every stamp the store
/// holds. Run it on two Macs signed into the same iCloud account and the
/// second one seeing the first one's stamp is the proof — `synchronize()`
/// returning true only means the write was queued locally.
///
/// Deliberately touches nothing real: its own key prefix, no settings, no
/// dictionary, no transcripts. Delete this file when the question is answered.
@MainActor
enum CloudSyncSpike {
    private static let keyPrefix = "spike.stamp."
    private static let store = NSUbiquitousKeyValueStore.default

    /// Never on the launch path — `synchronize()` is cheap and non-blocking,
    /// but nothing speculative goes in front of the first hotkey press.
    static func run() {
        let host = Host.current().localizedName ?? "unknown-mac"
        let key = keyPrefix + host
        let stamp = ISO8601DateFormatter().string(from: Date())

        // Read before writing. Reporting after a write proves nothing — it
        // would echo back the value still in this process's memory. Seeing the
        // *previous* run's stamp here is what proves the store survives
        // process death, which in-memory state would not.
        report(context: "on launch, before writing")

        store.set(stamp, forKey: key)
        let queued = store.synchronize()
        PushLogger.log("CloudSyncSpike: wrote \(key) synchronize=\(queued)")

        // The interesting event: another machine's write arriving here.
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int ?? -1
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            // The queue is .main, but the closure is nonisolated to the compiler.
            MainActor.assumeIsolated {
                PushLogger.log("CloudSyncSpike: external change reason=\(reason) keys=\(changed)")
                report(context: "after external change")
            }
        }
    }

    /// Every stamp currently in the store, whichever machine wrote it.
    private static func report(context: String) {
        let stamps = store.dictionaryRepresentation
            .filter { $0.key.hasPrefix(keyPrefix) }
            .map { "\($0.key.dropFirst(keyPrefix.count))=\($0.value)" }
            .sorted()

        if stamps.isEmpty {
            PushLogger.log("CloudSyncSpike: store empty \(context) — KVS not returning data")
        } else {
            PushLogger.log("CloudSyncSpike: \(stamps.count) stamp(s) \(context): \(stamps.joined(separator: ", "))")
        }
    }
}
