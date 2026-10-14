import Foundation
import CryptoKit
import Observation
import PUSHCore

/// "Learn from my writing and voice" (Settings → Personal; off by default).
/// Keeps what the user wrote in each field where Type is active — dictations
/// included, since a paste asks for a suggestion and that reads the field —
/// scrubbed of secrets, sealed with a key that lives in this Mac's Keychain,
/// never synced, and
/// offers the passages closest to what they are writing now as examples in
/// the prompt. Delete All removes the file and the key.
///
/// The field being written is held apart (`active`) and only joins the
/// history when the user moves on, so a draft is never its own example.
@MainActor
@Observable
final class TypingHistoryStore {
    static let shared = TypingHistoryStore()

    static let enabledKey = "typing.history.enabled"
    static let excludedKey = "typing.history.excludedApps"
    /// Per Mac, like the switch itself.
    static let pausedUntilKey = "typing.history.pausedUntil"
    /// Oldest go first past this; old writing says little about how the
    /// user writes now, and the index stays quick to rebuild.
    static let maximumRecords = 5_000
    /// "ok", a search term: not worth keeping.
    static let minimumCharacters = 20

    var isOn: Bool = UserDefaults.standard.bool(forKey: enabledKey) {
        didSet {
            UserDefaults.standard.set(isOn, forKey: Self.enabledKey)
            if isOn { Task { await load() } } else { finishActive() }
            if isOn != oldValue { LearnedWritingSync.shared.settingsChanged() }
        }
    }

    /// Apps whose text is never kept (Type may still suggest there).
    var excludedApps: [String] = UserDefaults.standard.stringArray(forKey: excludedKey) ?? [] {
        didSet { UserDefaults.standard.set(excludedApps, forKey: Self.excludedKey) }
    }

    private var pause = LearningPause(until: (UserDefaults.standard.object(forKey: pausedUntilKey) as? Date))
    @ObservationIgnored private var pauseEndTask: Task<Void, Never>?

    /// "Pause learning": nothing is kept until this time. Setting it drops the
    /// field being written, so what was typed just before pressing Pause is
    /// not kept either.
    var pausedUntil: Date? {
        get { pause.isPaused() ? pause.until : nil }
        set {
            pause.until = newValue
            UserDefaults.standard.set(newValue, forKey: Self.pausedUntilKey)
            if newValue != nil { active = nil; pendingDictation = nil }
            schedulePauseEnd()
        }
    }

    /// Clears an expired pause so the menu stops saying "Paused until".
    private func schedulePauseEnd() {
        pauseEndTask?.cancel()
        guard let until = pause.until, until > Date() else { return }
        pauseEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
            guard !Task.isCancelled, let self, self.pause.until == until else { return }
            self.pausedUntil = nil
        }
    }

    // MARK: - Sharing between Macs

    static let clearedAtKey = "typing.history.clearedAt"

    /// When Delete All last ran while sharing. Travels with the history so a
    /// Mac that was offline does not hand the old writing back.
    private var clearedAt: Date? {
        get { UserDefaults.standard.object(forKey: Self.clearedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.clearedAtKey) }
    }

    var snapshot: TypingHistorySnapshot { TypingHistorySnapshot(clearedAt: clearedAt, records: records) }

    /// Merge what another Mac published. Returns whether this Mac's history
    /// changed (and so is worth publishing again).
    func mergeRemote(_ remote: TypingHistorySnapshot) async -> Bool {
        guard isOn, !unreadable else { return false }
        await load()
        guard !unreadable else { return false }
        let merged = TypingHistorySync.merge(snapshot, remote)
        clearedAt = merged.clearedAt
        guard merged.records != records else { return merged != remote }
        records = merged.records
        rebuildIndex()
        scheduleSave()
        return true
    }

    /// Take the skipped apps from UserDefaults, which iCloud sync has just
    /// written to. The switch is not here: it is copied only when the user
    /// confirms it (`CloudSync.adoptFromOtherMac`).
    func reloadFromDefaults() {
        let d = UserDefaults.standard
        let excluded = d.stringArray(forKey: Self.excludedKey) ?? []
        if excluded != excludedApps { excludedApps = excluded }
    }

    private(set) var records: [TypingHistoryRecord] = []
    private(set) var passageCount = 0
    /// The file is there but would not open (its key is gone): nothing is
    /// recorded, so it is never overwritten with less. Delete All clears it.
    private(set) var unreadable = false

    private var loaded = false
    private var index: TypingHistoryIndex?
    /// The user's phrasing habits, from all their finished writing in every
    /// app (style travels; content stays in its window).
    private var habits: TypingHabits?
    private var active: (element: Int, bundleID: String, windowTitle: String?, text: String, dictated: [String])?
    /// The last dictation pasted, until a field read shows where it landed.
    private var pendingDictation: (text: String, at: Date)?
    private var saveTask: Task<Void, Never>?
    /// Bumped by Delete All, so a load or save already running is dropped.
    private var generation = 0

    private init() {
        if isOn { Task { await load() } }
        schedulePauseEnd()
    }

    // MARK: - Recording

    /// Called for each suggestion request, after every check that decides
    /// Type may run here — so nothing is kept where Type stays quiet (secure,
    /// sign-in and terminal fields, excluded apps).
    func observe(element: Int, bundleID: String?, windowTitle: String?, before: String) {
        guard isOn, loaded, !unreadable, let bundleID, !excludedApps.contains(bundleID) else { return }
        guard pause.mayKeep(element: element) else { return }
        if let current = active, current.element == element,
           TypingHistoryContinuity.isSameWriting(old: current.text, new: before) {
            active?.text = before
            claimDictation(in: before)
            return
        }
        finishActive()
        active = (element, bundleID, windowTitle, before, [])
        claimDictation(in: before)
    }

    /// A dictation is about to be pasted: tag it as dictated if it shows up
    /// in the field being written in the next few seconds.
    func noteDictation(_ text: String) {
        guard isOn, !pause.isPaused() else { return }
        let scrubbed = TypingHistoryScrubber.scrub(text).trimmingCharacters(in: .whitespacesAndNewlines)
        pendingDictation = scrubbed.isEmpty ? nil : (scrubbed, Date())
    }

    private func claimDictation(in before: String) {
        guard let pending = pendingDictation else { return }
        if Date().timeIntervalSince(pending.at) > 15 { pendingDictation = nil; return }
        guard before.contains(pending.text) else { return }
        active?.dictated.append(pending.text)
        pendingDictation = nil
    }

    /// The user's usual next words, when they have a clear habit here.
    func habitContinuation(before: String) -> String? {
        guard isOn else { return nil }
        return habits?.continuation(after: before)
    }

    /// The field being written joins the history.
    private func finishActive() {
        guard let current = active else { return }
        active = nil
        let text = TypingHistoryScrubber.scrub(current.text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.minimumCharacters, loaded, !unreadable else { return }
        // An earlier, shorter copy of the same writing (the user came back to
        // the note) is replaced rather than kept twice.
        records.removeAll { $0.bundleID == current.bundleID && text.contains($0.text.prefix(200)) }
        let dictated = current.dictated.filter { text.contains($0) }
        records.append(TypingHistoryRecord(text: text, bundleID: current.bundleID, windowTitle: current.windowTitle,
                                           dictated: dictated.isEmpty ? nil : dictated))
        if records.count > Self.maximumRecords { records.removeFirst(records.count - Self.maximumRecords) }
        rebuildIndex()
        scheduleSave()
    }

    // MARK: - Examples

    /// Up to two past passages on the topic of what is being written, from
    /// the same app and window.
    func examples(before: String, bundleID: String?, windowTitle: String?) -> [String] {
        guard isOn, let index else { return [] }
        let query = [TypingHistoryQuery.stableText(before), windowTitle ?? ""].joined(separator: " ")
        return index.examples(query: query, bundleID: bundleID, windowTitle: windowTitle, currentText: before)
    }

    // MARK: - Storage

    func load() async {
        guard !loaded else { return }
        let started = generation
        let result = await Task.detached(priority: .utility) { () -> Result<[TypingHistoryRecord], Error> in
            Result { try TypingHistoryVault.read() }
        }.value
        guard started == generation else { return }
        switch result {
        case .success(let stored):
            records = stored
            unreadable = false
            PushLogger.log("TypingHistoryStore: loaded \(stored.count) records")
        case .failure(let error):
            unreadable = true
            PushLogger.log("TypingHistoryStore: history would not open: \(error)")
        }
        loaded = true
        rebuildIndex()
        writeAssessmentIfAsked()
    }

    // MARK: - Assessment

    /// `defaults write com.push.voicetotext typing.assessLearning -bool true`,
    /// then relaunch: writes learning-assessment.md next to the history —
    /// numbers only, never a word of the text — and clears the switch.
    static let assessKey = "typing.assessLearning"

    private func writeAssessmentIfAsked() {
        guard UserDefaults.standard.bool(forKey: Self.assessKey), !unreadable else { return }
        UserDefaults.standard.removeObject(forKey: Self.assessKey)
        let snapshot = records
        Task.detached(priority: .utility) {
            let report = TypingLearningReport.make(records: snapshot)
            let url = TypingHistoryVault.fileURL.deletingLastPathComponent().appendingPathComponent("learning-assessment.md")
            try? report.write(to: url, atomically: true, encoding: .utf8)
            PushLogger.log("TypingHistoryStore: learning assessment written (\(snapshot.count) records)")
        }
    }

    private func rebuildIndex() {
        let snapshot = records
        let started = generation
        Task {
            let (built, learned) = await Task.detached(priority: .utility) {
                (TypingHistoryIndex(records: snapshot), TypingHabits(texts: snapshot.map(\.text)))
            }.value
            guard started == generation else { return }
            index = built
            habits = learned
            passageCount = built.passageCount
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard loaded, !unreadable else { return }
        let snapshot = records
        do {
            try TypingHistoryVault.write(snapshot)
            LearnedWritingSync.shared.pushSoon()
        } catch {
            PushLogger.log("TypingHistoryStore: save failed: \(error)")
        }
    }

    /// At quit: the field being written joins the history, and it is written now.
    func flush() {
        guard isOn else { return }
        finishActive()
        saveTask?.cancel()
        save()
    }

    /// Everything goes: the records, the file and its key.
    func deleteAll() {
        generation &+= 1
        saveTask?.cancel()
        active = nil
        records = []
        index = nil
        habits = nil
        pendingDictation = nil
        passageCount = 0
        unreadable = false
        loaded = true
        TypingHistoryVault.destroy()
        // Sharing: the empty history goes to iCloud with the moment of this
        // deletion, so every Mac drops what it held from before it.
        if LearnedWritingSync.shared.isActive {
            clearedAt = Date()
            LearnedWritingSync.shared.publishDeletion()
        }
        PushLogger.log("TypingHistoryStore: deleted all history")
    }
}

/// The sealed file in Application Support and its key in the Keychain.
enum TypingHistoryVault {
    static let fileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PUSH/TypingHistory.sealed")

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.push.voicetotext.typing-history",
        kSecAttrAccount as String: "key",
    ]

    enum Failure: Error { case keyMissing }

    /// No file yet: no history.
    static func read() throws -> [TypingHistoryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let key = loadKey() else { throw Failure.keyMissing }
        return try TypingHistoryCodec.open(data, key: key)
    }

    static func write(_ records: [TypingHistoryRecord]) throws {
        let key = try loadKey() ?? makeKey()
        let sealed = try TypingHistoryCodec.seal(records, key: key)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sealed.write(to: fileURL, options: .atomic)
    }

    static func destroy() {
        try? FileManager.default.removeItem(at: fileURL)
        SecItemDelete(query as CFDictionary)
    }

    private static func loadKey() -> SymmetricKey? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func makeKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        var add = query
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        // This Mac only, never iCloud Keychain: the history must not travel.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return key
    }
}
