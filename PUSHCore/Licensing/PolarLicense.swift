import Foundation
import IOKit

/// Where licence keys are checked. Polar is PUSH's merchant of record: it
/// sells the key and counts the Macs it is used on.
///
/// The licence endpoints are Polar's "customer portal" ones, built for
/// desktop apps: no access token, only the organization's ID, so nothing
/// secret ships inside PUSH. Sandbox until launch; production swaps in the
/// live organization's ID and host.
public struct PolarConfig: Sendable, Equatable {
    public let baseURL: URL
    public let organizationID: String
    /// The $35 product: one key, 3 Macs. The $12 add-on adds one more.
    public let productIDs: [String]
    /// Polar's checkout for the $35 product, for the app's "Buy PUSHTYPE".
    public let checkoutURL: URL
    /// The $12 add-on. It adds one place to the buyer's main key (the
    /// website's webhook sets the key's limit to 3 plus the Extra Macs paid),
    /// so the new Mac activates with the main key like the others.
    public let addMacCheckoutURL: URL
    /// Polar's customer portal: the buyer signs in with their email and a
    /// code, and sees their key, their download and which Macs use the key.
    public let portalURL: URL

    public static let sandbox = PolarConfig(
        baseURL: URL(string: "https://sandbox-api.polar.sh")!,
        organizationID: "0673c8e8-a8e6-4c1b-9cc1-5ff5d0c33037",
        productIDs: ["68857672-cc5b-45d4-8b10-abf40f523a11", "9deeaf9c-0f19-4e76-aad4-48826f58e2c2"],
        checkoutURL: URL(string: "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_4WHp8Y9ugKlJNeBVvYraMzq5KC9XTb0RIa5a32KWAZk/redirect")!,
        addMacCheckoutURL: URL(string: "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_HEce7BcHyVzWkIfAxiIQ9yYd7nztXdKsjwede2iyJDB/redirect")!,
        portalURL: URL(string: "https://sandbox.polar.sh/pushtype/portal")!)

    /// The live store (organization "pushtype"). Checkout links carry one
    /// product each: the website's Buy and the app's "add this Mac" must not
    /// offer the other.
    public static let production = PolarConfig(
        baseURL: URL(string: "https://api.polar.sh")!,
        organizationID: "d5c12043-0896-4c20-99a9-bbe1e2a833f1",
        productIDs: ["e05a47f1-acab-4221-af17-41dcb56a94e4", "b764aace-6737-4932-9028-75b890ac4c11"],
        checkoutURL: URL(string: "https://api.polar.sh/v1/checkout-links/polar_cl_ArikCs6D9ybDAfy0Hw5dPnjIqbhVBr7gKZYQx4QxxOY/redirect")!,
        addMacCheckoutURL: URL(string: "https://api.polar.sh/v1/checkout-links/polar_cl_vJwZTQYxnZStBuc837CtUnfAJ0Jp8fTjCLELa2ef7kZ/redirect")!,
        portalURL: URL(string: "https://polar.sh/pushtype/portal")!)

    /// What the app uses: the live store in a release build, the sandbox in a
    /// debug build so development never touches real orders.
    #if DEBUG
    public static let current = sandbox
    #else
    public static let current = production
    #endif
}

/// A licence as Polar reports it on this Mac.
public struct LicenseActivation: Sendable, Equatable, Codable {
    /// Polar's ID for this Mac's seat; needed to validate or free it.
    public let activationID: String
    /// The key with most characters hidden ("****-1234"), safe to show.
    public let displayKey: String
    /// How many Macs this key allows, if Polar limits it.
    public let activationLimit: Int?

    public init(activationID: String, displayKey: String, activationLimit: Int?) {
        self.activationID = activationID
        self.displayKey = displayKey
        self.activationLimit = activationLimit
    }
}

public enum LicenseError: Error, Equatable, Sendable {
    /// Polar has no such key (or it was revoked and is gone).
    case notFound
    /// The key exists but cannot be used here: every seat is taken, or it
    /// was disabled or refunded. Polar says which in `detail`.
    case refused(detail: String)
    /// No answer — offline, Polar down, or a timeout. Never a reason to stop
    /// someone dictating.
    case unreachable
    /// An answer we could not read. Treated like `unreachable`.
    case unexpected(status: Int)
}

/// Talks to Polar's licence-key endpoints. Stateless; storing the result is
/// the app's job (`LicenseStore`, in the Keychain).
public struct PolarLicenseClient: Sendable {
    public let config: PolarConfig
    private let session: URLSession

    public init(config: PolarConfig = .current, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            // Explicit timeouts: URLSession's defaults wait up to 7 days for a
            // resource, and a licence check must never hang anything.
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 15
            c.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: c)
        }
    }

    /// Take a seat for this Mac. `label` is what the buyer sees in Polar next
    /// to the seat — the Mac's model, never its name (`MacModelLabel`).
    public func activate(key: String, label: String) async throws -> LicenseActivation {
        let body: [String: Any] = [
            "key": key.trimmingCharacters(in: .whitespacesAndNewlines),
            "organization_id": config.organizationID,
            "label": label,
        ]
        let json = try await post("/v1/customer-portal/license-keys/activate", body)
        guard let id = json["id"] as? String else { throw LicenseError.unexpected(status: 200) }
        let licenseKey = json["license_key"] as? [String: Any] ?? [:]
        return LicenseActivation(
            activationID: id,
            displayKey: (licenseKey["display_key"] as? String) ?? Self.masked(key),
            activationLimit: licenseKey["limit_activations"] as? Int)
    }

    /// Whether this Mac's seat is still good. Throws `.notFound` for a key
    /// that was revoked or a seat that was freed elsewhere.
    public func validate(key: String, activationID: String) async throws {
        let body: [String: Any] = [
            "key": key.trimmingCharacters(in: .whitespacesAndNewlines),
            "organization_id": config.organizationID,
            "activation_id": activationID,
        ]
        let json = try await post("/v1/customer-portal/license-keys/validate", body)
        if let status = json["status"] as? String, status != "granted" {
            throw LicenseError.refused(detail: status)
        }
    }

    /// Free this Mac's seat so the key can be used on another.
    public func deactivate(key: String, activationID: String) async throws {
        let body: [String: Any] = [
            "key": key.trimmingCharacters(in: .whitespacesAndNewlines),
            "organization_id": config.organizationID,
            "activation_id": activationID,
        ]
        _ = try await post("/v1/customer-portal/license-keys/deactivate", body)
    }

    // MARK: - Transport

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        switch status {
        case 200..<300: return json
        case 404: throw LicenseError.notFound
        case 403: throw LicenseError.refused(detail: (json["detail"] as? String) ?? "not allowed")
        case 400, 422: throw LicenseError.refused(detail: Self.detail(json) ?? "invalid key")
        default: throw LicenseError.unexpected(status: status)
        }
    }

    private static func detail(_ json: [String: Any]) -> String? {
        if let s = json["detail"] as? String { return s }
        if let list = json["detail"] as? [[String: Any]], let first = list.first?["msg"] as? String { return first }
        return nil
    }

    /// Last four characters, the rest hidden — for when Polar sends no
    /// display form.
    public static func masked(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return "****-" + k.suffix(4)
    }
}

/// The label Polar shows next to a seat: "Mac mini (M4)". The Mac's model and
/// chip, never its name — "Elias's MacBook Pro" is personal information the
/// privacy policy promises not to send.
public enum MacModelLabel {
    /// `productName` is the model with its year ("Mac mini (2024)");
    /// `chip` is the CPU brand ("Apple M4 Pro").
    public static func label(productName: String?, chip: String?) -> String {
        var model = (productName ?? "Mac").trimmingCharacters(in: .whitespaces)
        if let paren = model.range(of: " (", options: .backwards), model.hasSuffix(")") {
            model = String(model[..<paren.lowerBound])
        }
        if model.isEmpty { model = "Mac" }
        let chipName = (chip ?? "").replacingOccurrences(of: "Apple ", with: "")
            .trimmingCharacters(in: .whitespaces)
        return chipName.isEmpty ? model : "\(model) (\(chipName))"
    }

    /// This Mac's label, from the device tree and the CPU brand string.
    public static func current() -> String {
        label(productName: productName(), chip: sysctlString("machdep.cpu.brand_string"))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// "Mac mini (2024)" from IODeviceTree:/product on Apple silicon.
    private static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }
}
