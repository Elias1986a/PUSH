import AppKit
import Security
import PUSHCore

/// The licence on this Mac, as the app knows it.
///
/// The key and Polar's activation ID live in the Keychain, not in
/// UserDefaults: a key is a credential, and UserDefaults is a plain plist
/// that iCloud settings sync and backups copy around. The record is this
/// Mac's (a seat is per Mac); the key alone is also kept in the user's iCloud
/// Keychain, so their other Macs can activate without asking.
///
/// Once the store is open (`isOffered`), `allowsUse` gates Talk, TYPE, the
/// wake word and the teleprompter. No trial: the 14-day refund is the trial.
@MainActor
@Observable
final class LicenseModel {
    static let shared = LicenseModel()

    /// Whether Settings shows the Licence pane. Off until PUSH is sold: the
    /// checkout links are still Polar's sandbox, and the user's own copies
    /// have no key. Turn on at launch, with the production `PolarConfig`.
    /// Until then `defaults write com.push.voicetotext licence.offered -bool
    /// true` shows it on one Mac, for a test purchase against the sandbox.
    static var isOffered: Bool { UserDefaults.standard.bool(forKey: "licence.offered") }

    struct Stored: Codable, Equatable {
        var key: String
        var activation: LicenseActivation
        var lastValidated: Date
    }

    private(set) var stored: Stored?
    private(set) var isWorking = false
    /// A sentence for the user after the last action, if it needs one.
    private(set) var message: String?
    /// The last activation was refused because the key is on all its Macs:
    /// the moment to offer an extra Mac or the portal to free one.
    private(set) var refusedForLimit = false

    /// Set once this Mac has held a licence. iCloud activates a Mac on its own
    /// only the first time: after Remove This Mac, or a seat freed from another
    /// Mac, it waits for the user, or the key would take the place straight back.
    private static let activatedHereKey = "licence.everActivatedHere"

    /// How often a working licence is re-checked with Polar.
    static let revalidateInterval: TimeInterval = 24 * 60 * 60

    /// How long the app keeps working without a successful check: offline is
    /// fine, but not forever, or a refunded key behind a blocked polar.sh
    /// would never stop (user, 2026-10-14: 30 days).
    nonisolated static let offlineAllowance: TimeInterval = 30 * 24 * 60 * 60

    /// A key from an activation link while this Mac already holds a different
    /// one. Never applied on its own: any web page can open such a link, and
    /// it must not swap a working licence (and the one in iCloud) unasked.
    /// The License pane offers it.
    private(set) var offeredKey: String?

    private var wakeObserver: NSObjectProtocol?
    private var checkTimer: Timer?

    private let client: PolarLicenseClient
    private let keychain: LicenseKeychain
    private let synced: SyncedLicenseKey

    init(client: PolarLicenseClient = PolarLicenseClient(), keychain: LicenseKeychain = LicenseKeychain(),
         synced: SyncedLicenseKey = SyncedLicenseKey()) {
        self.client = client
        self.keychain = keychain
        self.synced = synced
        #if DEBUG
        // A debug build cannot read the signed app's keychain item without a
        // password prompt; opening the wizard on a chosen page for screenshots
        // (PUSH_ONBOARDING_STEP) must not ask for one.
        if ProcessInfo.processInfo.environment["PUSH_ONBOARDING_STEP"] != nil {
            self.stored = nil
            return
        }
        #endif
        self.stored = keychain.load()
    }

    var isLicensed: Bool { stored != nil }

    /// Whether Talk and TYPE may run: always until the store opens, then only
    /// with a licence checked with Polar in the last 30 days. No trial; the
    /// 14-day refund is the trial.
    var allowsUse: Bool { !Self.isOffered || (isLicensed && !needsCheck()) }

    /// Too long since Polar last confirmed this Mac's seat. A date in the
    /// future counts too: no real check is dated there, so the record was
    /// edited, and treating it as fresh would let it skip every check.
    func needsCheck(now: Date = Date()) -> Bool {
        guard let stored else { return false }
        return Self.isOverdue(lastValidated: stored.lastValidated, now: now)
    }

    nonisolated static func isOverdue(lastValidated: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(lastValidated)
        return elapsed < 0 || elapsed >= offlineAllowance
    }

    /// Put the way to activate in front of the user: the welcome window's
    /// licence page if it is open, otherwise Settings ▸ Licence. A Mac that
    /// has a licence but is overdue for a check tries the check first, and
    /// only shows the pane if that does not settle it.
    func askForLicence() {
        guard stored == nil else {
            Task {
                await revalidate(force: true)
                if !allowsUse { presentLicence() }
            }
            return
        }
        presentLicence()
    }

    private func presentLicence() {
        if OnboardingWindowController.shared.isShowing {
            OnboardingWindowController.shared.show()
        } else {
            SettingsWindowController.shared.show(pane: .licence)
        }
    }

    /// The key another of the user's Macs put in their iCloud Keychain.
    var iCloudKey: String? { synced.load() }

    /// A key the user has just copied (from Polar's email, say). Read only
    /// while the licence step or pane is on screen, never in the background.
    var clipboardKey: String? { LicenseKeyText.key(in: NSPasteboard.general.string(forType: .string)) }

    /// A new Mac signed in to the same Apple Account: take a seat with the key
    /// from iCloud, once, without asking.
    func activateFromICloudIfNeeded() async {
        guard Self.isOffered, !isLicensed, !UserDefaults.standard.bool(forKey: Self.activatedHereKey),
              let key = synced.load() else { return }
        PushLogger.log("License: activating with the key from iCloud Keychain")
        await activate(key: key)
        // A fourth Mac found the key but no free place. That happened at
        // launch, unseen: put the choices in front of the user.
        if refusedForLimit { SettingsWindowController.shared.show(pane: .licence) }
    }

    /// Take a seat for this Mac with `key`.
    func activate(key: String) async {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isWorking else { return }
        isWorking = true
        message = nil
        refusedForLimit = false
        defer { isWorking = false }
        do {
            var activation = try await client.activate(key: key, label: MacModelLabel.current())
            // Validate at once: it is what marks the key as in use on Polar's
            // side (the website's seat merging leaves a key alone only once
            // it has been validated), and it reads the current Mac limit.
            if let limit = try? await client.validate(key: key, activationID: activation.activationID) {
                activation.activationLimit = limit
            }
            let record = Stored(key: key, activation: activation, lastValidated: Date())
            keychain.save(record)
            stored = record
            UserDefaults.standard.set(true, forKey: Self.activatedHereKey)
            // The customer's first key is their main key whatever it started as
            // (a single given away, say, later raised by buying the three), so
            // whichever key this is goes to the user's other Macs too.
            synced.save(key)
            PushLogger.log("License: activated on this Mac")
        } catch let error as LicenseError {
            message = Self.sentence(for: error, activating: true)
            if case .refused(let detail) = error, Self.isLimit(detail) { refusedForLimit = true }
            PushLogger.log("License: activation failed (\(error))")
        } catch {
            message = Self.sentence(for: .unreachable, activating: true)
        }
    }

    /// Give this Mac's seat back, so the key can go on another Mac.
    func removeThisMac() async {
        guard let record = stored, !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await client.deactivate(key: record.key, activationID: record.activation.activationID)
        } catch LicenseError.notFound {
            // Already gone on Polar's side; forgetting it here is all that's left.
        } catch {
            message = "Couldn't reach Polar to free this Mac's place. Check your connection and try again."
            return
        }
        keychain.delete()
        stored = nil
        PushLogger.log("License: removed from this Mac")
    }

    /// Re-check with Polar at most once a day. Offline or an odd answer
    /// changes nothing for 30 days: the app works offline and must not stop
    /// because a server did not answer. Polar saying the key or seat is gone
    /// does, and so does a month without any answer (`needsCheck`).
    func revalidateIfDue(now: Date = Date()) async {
        await revalidate(force: false, now: now)
    }

    /// `force`: check now whatever the date (the Check Now button, or a press
    /// refused for being overdue).
    func revalidate(force: Bool, now: Date = Date()) async {
        guard let record = stored, !isWorking else { return }
        let elapsed = now.timeIntervalSince(record.lastValidated)
        guard force || elapsed < 0 || elapsed >= Self.revalidateInterval else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let limit = try await client.validate(key: record.key, activationID: record.activation.activationID)
            var updated = record
            updated.lastValidated = now
            if let limit { updated.activation.activationLimit = limit }
            keychain.save(updated)
            stored = updated
            message = nil
        } catch LicenseError.notFound {
            forget("This Mac's license is no longer active. It may have been removed from another Mac or refunded.")
        } catch LicenseError.refused(let detail) {
            forget("This Mac's license is no longer active (\(detail)). If you bought more than once, your Macs share your first key: use Activate on the thank-you page, or the key from your other Mac.")
        } catch {
            // Unreachable or unreadable: try again later, and say so once it
            // is the reason the app has stopped.
            if needsCheck(now: now) {
                message = "PUSHTYPE hasn't been able to check your license with Polar for 30 days. Connect to the internet and press Check Now."
            }
        }
    }

    /// Re-check on wake and every few hours while running: a menu-bar app runs
    /// for weeks, and a check only at launch let a refund go unnoticed until
    /// the next relaunch. `revalidateIfDue` still asks Polar at most once a day.
    func startPeriodicChecks() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await LicenseModel.shared.revalidateIfDue() }
        }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in await LicenseModel.shared.revalidateIfDue() }
        }
    }

    /// An activation link brought `key` while this Mac has a licence: hold it
    /// for the License pane to offer, rather than activate it.
    func offer(key: String) {
        guard stored != nil, stored?.key != key else { return }
        offeredKey = key
    }

    func declineOfferedKey() { offeredKey = nil }

    /// The user chose the offered key: give this Mac's place on the old key
    /// back first, so it does not linger on Polar, then activate the new one.
    func switchToOfferedKey() async {
        guard let key = offeredKey else { return }
        offeredKey = nil
        await removeThisMac()
        guard stored == nil else { return }   // could not free the old place; message says why
        await activate(key: key)
    }

    private func forget(_ sentence: String) {
        keychain.delete()
        stored = nil
        message = sentence
        PushLogger.log("License: Polar no longer recognizes this Mac's seat")
    }

    static func isLimit(_ detail: String) -> Bool {
        let d = detail.lowercased()
        return d.contains("limit") || d.contains("activations")
    }

    static func sentence(for error: LicenseError, activating: Bool) -> String {
        switch error {
        case .notFound:
            return "That key wasn't found. Copy it again from the email Polar sent you, all of it."
        case .refused(let detail) where isLimit(detail):
            return "This license is already on all its Macs. Add this Mac for $12 (buy it with the same email), or free a place by removing one you no longer use."
        case .refused(let detail):
            return "Polar didn't accept this key: \(detail). If you bought more than once, your Macs share your first key: use Activate on the thank-you page, or the key from your other Mac."
        case .unreachable, .unexpected:
            return "Couldn't reach Polar. Check your internet connection and try again."
        }
    }
}

/// One Keychain item holding the licence record.
struct LicenseKeychain {
    // A debug build keeps its own item. It is not signed like the installed
    // app, so reading that app's item made macOS ask for the login password,
    // once per launch: a screenshot pass raised fourteen prompts (2026-10-14).
    #if DEBUG
    var service = "com.push.voicetotext.licence.debug"
    #else
    var service = "com.push.voicetotext.licence"
    #endif
    private let account = "licence"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> LicenseModel.Stored? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(LicenseModel.Stored.self, from: data)
    }

    func save(_ record: LicenseModel.Stored) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            // This Mac only: a seat is per Mac, so the record must not follow
            // the user to another Mac through iCloud Keychain.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// The key alone, in the user's iCloud Keychain (end-to-end encrypted), so a
/// licence bought once reaches all their Macs. Needs the data-protection
/// keychain, which the signed app has through its application identifier;
/// an unsigned `swift run` build quietly does without.
struct SyncedLicenseKey {
    var service = "com.push.voicetotext.licence.key"
    private let account = "key"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: true,
         kSecUseDataProtectionKeychain as String: true]
    }

    func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String) {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(add as CFDictionary, nil)
            if added != errSecSuccess { PushLogger.log("License: iCloud Keychain save failed (\(added))") }
        } else if status != errSecSuccess {
            PushLogger.log("License: iCloud Keychain update failed (\(status))")
        }
    }
}
