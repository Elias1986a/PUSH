import Foundation
import CryptoKit
import PUSHCore

/// Shares what Type has learned between the user's Macs, when they switch it
/// on (Settings ▸ Personal ▸ Share with my other Macs, per Mac).
///
/// The writing is compressed, sealed with a key that lives in iCloud Keychain
/// (end-to-end encrypted by Apple, the same way the licence key travels) and
/// put in iCloud's key-value store in chunks. Nothing here needs more
/// entitlements than settings sync already has. Only runs while this Mac is
/// learning, sharing and iCloud sync is on; a Mac with learning off neither
/// sends nor receives any writing.
@MainActor
final class LearnedWritingSync {
    static let shared = LearnedWritingSync()

    /// Per Mac. Seeded to a new Mac with the learning switch.
    static let shareKey = "typing.history.share"

    private let kvs = NSUbiquitousKeyValueStore.default
    private static let metaKey = "sync.history.meta"
    private static let chunkPrefix = "sync.history.chunk."
    private var pushTask: Task<Void, Never>?
    private var pulling = false
    private init() {}

    var isShareOn: Bool { UserDefaults.standard.bool(forKey: Self.shareKey) }

    var isActive: Bool {
        AppState.shared.iCloudSyncEnabled && TypingHistoryStore.shared.isOn
            && isShareOn && !TypingHistoryStore.shared.unreadable
    }

    /// The share switch or the learning switch changed: bring the copies together.
    func settingsChanged() {
        guard isActive else { return }
        Task {
            await pull()
            pushSoon(delay: 1)
        }
    }

    // MARK: - Push

    /// Publish this Mac's history, a little after the latest change so a run of
    /// saves is one write.
    func pushSoon(delay: TimeInterval = 20) {
        guard isActive else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.pushNow()
        }
    }

    private func pushNow() {
        guard isActive, let key = SyncedHistoryKey.loadOrCreate() else { return }
        let snapshot = TypingHistoryStore.shared.snapshot
        guard let chunks = try? TypingHistorySync.pack(snapshot, key: key) else { return }

        // Unchanged since the last publish (a pull that changed nothing here
        // must not bounce back): same digest, nothing to write.
        let digest = Self.digest(of: chunks)
        if (kvs.dictionary(forKey: Self.metaKey)?["digest"] as? String) == digest { return }

        let oldCount = (kvs.dictionary(forKey: Self.metaKey)?["count"] as? Int) ?? 0
        for (i, chunk) in chunks.enumerated() { kvs.set(chunk, forKey: Self.chunkPrefix + String(i)) }
        kvs.set(["count": chunks.count, "digest": digest, "at": Date().timeIntervalSince1970], forKey: Self.metaKey)
        if oldCount > chunks.count {
            for i in chunks.count..<oldCount { kvs.removeObject(forKey: Self.chunkPrefix + String(i)) }
        }
        kvs.synchronize()
        // Counts and bytes only — never the writing.
        PushLogger.log("LearnedWritingSync: published \(snapshot.records.count) record(s) in \(chunks.count) chunk(s)")
    }

    /// Delete All with sharing on: publish the empty history and the moment
    /// of the deletion now, so the other Macs drop what they hold.
    func publishDeletion() {
        pushTask?.cancel()
        pushNow()
    }

    // MARK: - Pull

    /// Merge what the other Macs published into this one.
    func pull() async {
        guard isActive, !pulling, let key = SyncedHistoryKey.load() else { return }
        pulling = true
        defer { pulling = false }
        guard let meta = kvs.dictionary(forKey: Self.metaKey), let count = meta["count"] as? Int, count > 0 else { return }
        var chunks: [Data] = []
        for i in 0..<count {
            // A chunk still on its way: try again when it arrives.
            guard let chunk = kvs.data(forKey: Self.chunkPrefix + String(i)) else { return }
            chunks.append(chunk)
        }
        guard let remote = try? TypingHistorySync.unpack(chunks, key: key) else {
            // Sealed with a different key (two Macs made one at the same time):
            // publish ours, and the Keychain settles on one.
            pushSoon(delay: 5)
            return
        }
        let changedHere = await TypingHistoryStore.shared.mergeRemote(remote)
        PushLogger.log("LearnedWritingSync: merged \(remote.records.count) remote record(s), changed here: \(changedHere)")
        if changedHere { pushSoon() }
    }

    /// Called when iCloud says the history keys changed.
    func remoteChanged() {
        Task { await pull() }
    }

    private static func digest(of chunks: [Data]) -> String {
        var hasher = SHA256()
        for chunk in chunks { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// The key that seals the history in transit, in the user's iCloud Keychain
/// (synchronizable, so every Mac on the Apple Account has it, and Apple
/// cannot read it). Apart from the key that seals the file on each Mac.
enum SyncedHistoryKey {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.push.voicetotext.history.sync",
        kSecAttrAccount as String: "key",
        kSecAttrSynchronizable as String: true,
        kSecUseDataProtectionKeychain as String: true,
    ]

    static func load() -> SymmetricKey? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    static func loadOrCreate() -> SymmetricKey? {
        if let key = load() { return key }
        let key = SymmetricKey(size: .bits256)
        var add = query
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return load() }
        return key
    }
}
