import Foundation
import Security
import PUSHCore

/// The licence on this Mac, as the app knows it.
///
/// The key and Polar's activation ID live in the Keychain, not in
/// UserDefaults: a key is a credential, and UserDefaults is a plain plist
/// that iCloud settings sync and backups copy around.
///
/// Nothing here stops dictation yet. What happens without a licence (a trial,
/// or not) is still to be decided; this is the part that knows whether there
/// is one.
@MainActor
@Observable
final class LicenseModel {
    static let shared = LicenseModel()

    struct Stored: Codable, Equatable {
        var key: String
        var activation: LicenseActivation
        var lastValidated: Date
    }

    private(set) var stored: Stored?
    private(set) var isWorking = false
    /// A sentence for the user after the last action, if it needs one.
    private(set) var message: String?

    /// How often a working licence is re-checked with Polar.
    static let revalidateInterval: TimeInterval = 24 * 60 * 60

    private let client: PolarLicenseClient
    private let keychain: LicenseKeychain

    init(client: PolarLicenseClient = PolarLicenseClient(), keychain: LicenseKeychain = LicenseKeychain()) {
        self.client = client
        self.keychain = keychain
        self.stored = keychain.load()
    }

    var isLicensed: Bool { stored != nil }

    /// Take a seat for this Mac with `key`.
    func activate(key: String) async {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let activation = try await client.activate(key: key, label: MacModelLabel.current())
            let record = Stored(key: key, activation: activation, lastValidated: Date())
            keychain.save(record)
            stored = record
            PushLogger.log("License: activated on this Mac")
        } catch let error as LicenseError {
            message = Self.sentence(for: error, activating: true)
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

    static func sentence(for error: LicenseError, activating: Bool) -> String {
        switch error {
        case .notFound:
            return "That key wasn't found. Copy it again from the email Polar sent you, all of it."
        case .refused(let detail) where detail.lowercased().contains("limit"):
            return "This key is already in use on all its Macs. Remove PUSH from one of them (Settings ▸ Licence ▸ Remove this Mac), or add a Mac for $10."
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
