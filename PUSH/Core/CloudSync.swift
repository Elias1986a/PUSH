import Foundation
import Combine
import PUSHCore

/// Syncs settings and the custom dictionary across the user's Macs through
/// iCloud key-value storage.
///
/// No account, no login, no server: KVS rides on whatever iCloud account the
/// Mac is already signed into, and each user's data stays in their own store.
/// Proven working unsandboxed on a Developer ID build — a write on one machine
/// reached another in about two seconds.
///
/// Capacity is not a concern: KVS allows 1MB and the payload here is settings
/// plus a dictionary measured in kilobytes.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    /// Settings mirrored across machines. Scalars only — each is its own KVS
    /// key so that changing the hotkey on one Mac and the preview size on
    /// another keeps both, which a single blob would not.
    ///
    /// `pillPosition` is deliberately absent: a notched MacBook and an external
    /// monitor are exactly the case where the same person wants different
    /// answers, so it stays per-machine.
    static let mirroredSettingKeys = [
        "selectedWhisperModel",
        "selectedHotkey",
        "playSoundOnStart",
        "wakeWordEnabled",
        "wakeWord",
        "doubleSpaceAfterSentence",
        "mediaBehavior",
        "showLivePreview",
        "previewSize",
        "resolveSelfCorrections"
    ]

    private static let dictionaryKey = "sync.dictionary"
    private static let settingPrefix = "sync.setting."

    /// A tombstone stops travelling once every machine has certainly seen it.
    /// Thirty days is far longer than any plausible gap between two Macs both
    /// being used, and the storage cost is a few bytes per deleted entry.
    static let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    private let store = NSUbiquitousKeyValueStore.default
    private var started = false
    /// Set while applying a remote change, so writing the merge result back to
    /// local storage doesn't bounce straight out to iCloud again.
    private var isApplyingRemote = false

    private init() {}

    // MARK: - Lifecycle

    /// Begin syncing. Safe to call more than once.
    func start() {
        guard !started, AppState.shared.iCloudSyncEnabled else { return }
        started = true

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.applyRemoteChange(note)
            }
        }

        // One observer rather than a hook in each setting's didSet: every
        // mirrored value already lives in UserDefaults, so this cannot miss one
        // that someone adds later. Coalesced because a single UI interaction
        // can post several times.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleSettingsPush()
            }
        }

        store.synchronize()
        pullAll()
        pushAll()
        PushLogger.log("CloudSync: started")
    }

    private var pendingSettingsPush: Task<Void, Never>?

    private func scheduleSettingsPush() {
        guard !isApplyingRemote else { return }
        pendingSettingsPush?.cancel()
        pendingSettingsPush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            guard let self, !self.isApplyingRemote else { return }
            for key in Self.mirroredSettingKeys { self.pushSetting(key) }
        }
    }

    // MARK: - Local → iCloud

    /// Entries are passed in rather than read back from `CorrectionsStore`.
    /// Reaching for the singleton here deadlocked: the store calls this from
    /// its own `didSet`, which runs during `CorrectionsStore.shared`'s one-time
    /// initialiser, so touching `.shared` from inside it re-enters
    /// `dispatch_once` and traps.
    func dictionaryDidChange(_ entries: [CorrectionsStore.Correction]) {
        guard started, !isApplyingRemote else { return }
        // Coalesced like the settings push: a row in Settings saves on every
        // keystroke, and iCloud's key-value store is not something to write to
        // once per letter typed.
        pendingDictionaryPush?.cancel()
        pendingDictionaryPush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            guard let self, !self.isApplyingRemote else { return }
            self.push(entries)
        }
    }

    private var pendingDictionaryPush: Task<Void, Never>?

    private func pushAll() {
        for key in Self.mirroredSettingKeys { pushSetting(key) }
        pushDictionary()
    }

    private func pushSetting(_ key: String) {
        guard let value = UserDefaults.standard.object(forKey: key) else { return }
        store.set(value, forKey: Self.settingPrefix + key)
    }

    private func pushDictionary() {
        push(CorrectionsStore.shared.allForSync)
    }

    private func push(_ entries: [CorrectionsStore.Correction]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        store.set(data, forKey: Self.dictionaryKey)
        // Counts and bytes only — dictionary contents are the user's words.
        PushLogger.log("CloudSync: pushed dictionary — \(entries.count) entr(ies), \(data.count) bytes")
    }

    // MARK: - iCloud → local

    private func applyRemoteChange(_ note: Notification) {
        let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        guard !changed.isEmpty else { return }

        isApplyingRemote = true
        defer { isApplyingRemote = false }

        for key in changed where key.hasPrefix(Self.settingPrefix) {
            pullSetting(String(key.dropFirst(Self.settingPrefix.count)))
        }
        if changed.contains(Self.dictionaryKey) {
            pullDictionary()
        }
        PushLogger.log("CloudSync: applied \(changed.count) remote key(s)")
    }

    private func pullAll() {
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        for key in Self.mirroredSettingKeys { pullSetting(key) }
        pullDictionary()
    }

    private func pullSetting(_ key: String) {
        guard Self.mirroredSettingKeys.contains(key),
              let value = store.object(forKey: Self.settingPrefix + key) else { return }
        UserDefaults.standard.set(value, forKey: key)
        AppState.shared.reloadFromDefaults()
    }

    private func pullDictionary() {
        guard let data = store.data(forKey: Self.dictionaryKey),
              let remote = try? JSONDecoder().decode([CorrectionsStore.Correction].self, from: data)
        else { return }

        let local = CorrectionsStore.shared.allForSync
        let merged = Self.mergeCorrections(local: local, remote: remote)
        CorrectionsStore.shared.applyMerged(alive: merged.alive, tombstones: merged.tombstones)

        PushLogger.log("CloudSync: merged dictionary — \(merged.alive.count) live, \(merged.tombstones.count) tombstone(s)")

        // The merge can hold more than iCloud does, or the same entries with a
        // newer edit this machine made while offline, so publish it back
        // whenever the result is not already what iCloud has.
        if !Self.payloadMatches(merged.alive + merged.tombstones, remote) {
            pushDictionary()
        }
    }

    // MARK: - Merge

    /// Reconcile two copies of the dictionary.
    ///
    /// There is no lead machine. The rules, in order:
    ///
    /// 1. **Union by id, newest wins.** An entry edited in two places resolves
    ///    to the later `modifiedAt`. Losing one edit to a personal dictionary
    ///    is recoverable in seconds; losing an entry is not, which is why
    ///    last-writer-wins is applied per entry and never to the list.
    /// 2. **A tombstone beats a live entry of the same id**, unless the live
    ///    one is strictly newer — that is a deliberate re-add after a delete.
    /// 3. **Deduplicate live entries by content**, keeping the oldest, so the
    ///    same correction added independently on two machines collapses to one
    ///    with a stable id rather than appearing twice.
    /// 4. **Expire tombstones** past `tombstoneLifetime`.
    nonisolated static func mergeCorrections(
        local: [CorrectionsStore.Correction],
        remote: [CorrectionsStore.Correction],
        now: Date = Date()
    ) -> (alive: [CorrectionsStore.Correction], tombstones: [CorrectionsStore.Correction]) {
        // 1 & 2 — one winner per id. `modifiedAt` is stamped at deletion too,
        // so a delete and an edit race on the same footing.
        var byID: [UUID: CorrectionsStore.Correction] = [:]
        for entry in local + remote {
            guard let existing = byID[entry.id] else {
                byID[entry.id] = entry
                continue
            }
            if entry.modifiedAt > existing.modifiedAt {
                byID[entry.id] = entry
            } else if entry.modifiedAt == existing.modifiedAt, entry.isDeleted {
                // Same instant: the deletion is the safer of the two to keep,
                // because it can be undone by re-adding and the reverse cannot.
                byID[entry.id] = entry
            }
        }

        let winners = Array(byID.values)

        // 4 — drop tombstones nobody needs any more.
        let tombstones = winners
            .filter(\.isDeleted)
            .filter { now.timeIntervalSince($0.deletedAt ?? now) < tombstoneLifetime }

        // 3 — collapse independent duplicates, oldest kept so the surviving id
        // is the one that has been around longest, but never at the cost of the
        // context one of them carries: `contentKey` ignores `entity`, so the
        // older copy is routinely the one that was never given a hint.
        var seen: [String: CorrectionsStore.Correction] = [:]
        for entry in winners where !entry.isDeleted {
            guard let existing = seen[entry.contentKey] else {
                seen[entry.contentKey] = entry
                continue
            }
            let older = entry.modifiedAt < existing.modifiedAt ? entry : existing
            let newer = entry.modifiedAt < existing.modifiedAt ? existing : entry
            seen[entry.contentKey] = carryingContext(into: older, from: newer)
        }

        // Stable order so the encoded blob doesn't churn between machines.
        let alive = seen.values.sorted {
            $0.modifiedAt == $1.modifiedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.modifiedAt < $1.modifiedAt
        }
        let sortedTombstones = tombstones.sorted {
            $0.modifiedAt == $1.modifiedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.modifiedAt < $1.modifiedAt
        }

        return (alive, sortedTombstones)
    }

    /// Fill in a missing hint from the copy that has one. Only ever adds
    /// information: a context the user typed on one Mac is never overwritten by
    /// the other Mac's silence.
    private nonisolated static func carryingContext(
        into base: CorrectionsStore.Correction,
        from other: CorrectionsStore.Correction
    ) -> CorrectionsStore.Correction {
        guard base.normalizedEntity == nil, let entity = other.normalizedEntity else { return base }
        var merged = base
        merged.entity = entity
        return merged
    }

    /// Whether a merge result is already what iCloud holds. Compared by content
    /// and not by count: a machine that comes back online holding the newer
    /// edit produces a same-sized list that the other Mac still needs.
    nonisolated static func payloadMatches(
        _ merged: [CorrectionsStore.Correction],
        _ remote: [CorrectionsStore.Correction]
    ) -> Bool {
        guard merged.count == remote.count else { return false }
        let byID = { (list: [CorrectionsStore.Correction]) in
            list.sorted { $0.id.uuidString < $1.id.uuidString }
        }
        return byID(merged) == byID(remote)
    }
}
