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
/// Nothing here stops dictation yet. What happens without a licence (a trial,
/// or not) is still to be decided; this is the part that knows whether there
/// is one.
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

    /// Whether Dictation and Type may run: always until the store opens, then
    /// only with a licence. No grace period; the 14-day refund is the trial.
    var allowsUse: Bool { !Self.isOffered || isLicensed }

    /// Put the way to activate in front of the user: the welcome window's
    /// licence page if it is open, otherwise Settings ▸ Licence.
    func askForLicence() {
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
            let activation = try await client.activate(key: key, label: MacModelLabel.current())
            let record = Stored(key: key, activation: activation, lastValidated: Date())
            keychain.save(record)
            stored = record
            UserDefaults.standard.set(true, forKey: Self.activatedHereKey)
            // An Extra Mac key is good for this one Mac: it must not follow the
            // user to the others through iCloud in place of the main key.
            if activation.activationLimit != 1 { synced.save(key) }
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
    /// changes nothing: dictation works offline and must not stop because a
    /// server did not answer. Only Polar saying the key or seat is gone does.
    func revalidateIfDue(now: Date = Date()) async {
        guard let record = stored, !isWorking,
              now.timeIntervalSince(record.lastValidated) >= Self.revalidateInterval else { return }
        do {
            try await client.validate(key: record.key, activationID: record.activation.activationID)
            var updated = record
            updated.lastValidated = now
            keychain.save(updated)
            stored = updated
        } catch LicenseError.notFound {
            forget("This Mac's licence is no longer active. It may have been removed from another Mac or refunded.")
        } catch LicenseError.refused(let detail) {
            forget("This Mac's licence is no longer active (\(detail)).")
        } catch {
            // Unreachable or unreadable: try again next launch.
        }
    }

    private func forget(_ sentence: String) {
        keychain.delete()
        stored = nil
        message = sentence
        PushLogger.log("License: Polar no longer recognises this Mac's seat")
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
            return "This licence is already on all its Macs. Add this Mac for $12, or free a place by removing one you no longer use."
        case .refused(let detail):
            return "Polar didn't accept this key: \(detail)."
        case .unreachable, .unexpected:
            return "Couldn't reach Polar. Check your internet connection and try again."
        }
    }
}

/// One Keychain item holding the licence record.
struct LicenseKeychain {
    var service = "com.push.voicetotext.licence"
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
