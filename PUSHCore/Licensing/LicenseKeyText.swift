import Foundation

/// Finding a licence key where a buyer leaves one: on the clipboard after
/// copying it from Polar's email, or in the link the thank-you page opens.
/// Pure, so it is pinned by tests.
public enum LicenseKeyText {
    /// Polar's keys are an uppercase UUID, optionally behind a prefix the
    /// seller sets ("PUSH-…"). Nothing else on a clipboard is mistaken for one.
    private static let pattern = try! NSRegularExpression(
        pattern: "^(?:[A-Z0-9_]{1,16}-)?[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$",
        options: [.caseInsensitive])

    /// The key in `text`, if `text` is one key and nothing more (surrounding
    /// spaces and line breaks aside, which copying from an email adds).
    public static func key(in text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 80 else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return pattern.firstMatch(in: trimmed, range: range) == nil ? nil : trimmed.uppercased()
    }

    /// The URL scheme the thank-you page's Activate button opens.
    public static let scheme = "pushtype"

    /// The key in `pushtype://activate?key=…`.
    public static func key(inActivationLink url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "activate",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        // Looser than the clipboard check: the link comes from our own page,
        // straight from Polar, so any key-shaped token is taken as given.
        guard let value = items.first(where: { $0.name == "key" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              (8...80).contains(value.count),
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return value
    }
}
