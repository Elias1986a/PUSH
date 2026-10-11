import Foundation

/// Fields Type stands down in, beyond password fields (refused everywhere).
/// After Cotabby's detectors (ideas, not code): a completion in a sign-in or
/// verification field guesses at the user's identity, and in Mail's header
/// rows Tab is how the writer moves to the next field.
public enum FieldPolicy {
    static let singleLineRoles: Set<String> = ["AXTextField", "AXComboBox", "AXSearchField"]

    static let credentialWords = [
        "email", "e-mail", "username", "user name", "user id", "login", "log in", "sign in", "phone",
        "mobile number", "password", "passcode", "pin", "one-time", "one time code", "verification code",
        "security code", "otp", "2fa", "two-factor", "authentication code", "card number", "cvc", "cvv",
        "expiry", "expiration",
    ]
    /// A label that describes writing about email or a phone ("Email subject").
    static let proseWords = ["subject", "message", "body", "preview", "title", "signature", "template",
                             "comment", "note", "notes", "reply", "search"]
    static let credentialIDParts: Set<String> = [
        "email", "mail", "username", "userid", "login", "logon", "signin", "passwd", "password", "pwd",
        "passcode", "otp", "totp", "mfa", "phone", "tel", "telephone", "mobile", "pin", "cvc", "cvv",
        "cardnumber", "identifierid", "onetimecode", "verificationcode", "securitycode", "authcode",
    ]

    /// Single-line fields only: a multi-line field labelled "email" is an
    /// email body, exactly where suggestions belong.
    public static func isCredentialField(role: String?, labels: [String?], domIdentifier: String?, text: String?) -> Bool {
        guard let role, singleLineRoles.contains(role) else { return false }
        if labels.contains(where: { $0.map(labelNamesCredential) ?? false }) { return true }
        if let domIdentifier, idNamesCredential(domIdentifier) { return true }
        if let text, text.contains("@"), !text.contains(where: \.isWhitespace) { return true }   // an address being typed
        return false
    }

    /// Mail: only the message body (a web area) gets suggestions.
    public static func isMailHeader(bundleID: String?, role: String?) -> Bool {
        bundleID?.lowercased() == "com.apple.mail" && role != "AXWebArea"
    }

    static func labelNamesCredential(_ label: String) -> Bool {
        let label = label.lowercased()
        guard credentialWords.contains(where: { containsWord($0, in: label) }) else { return false }
        return !proseWords.contains(where: { containsWord($0, in: label) })
    }

    /// "user_email", "loginEmail", "identifierId" name a credential; "emailSearch" does not.
    static func idNamesCredential(_ id: String) -> Bool {
        guard id.count <= 64 else { return false }
        let whole = id.lowercased().filter { $0.isLetter || $0.isNumber }
        if credentialIDParts.contains(whole) { return true }
        let parts = splitIdentifier(id)
        guard !parts.contains("search") else { return false }
        return parts.contains(where: credentialIDParts.contains)
    }

    /// Splits on separators and camelCase: "loginEmail" → ["login", "email"].
    static func splitIdentifier(_ id: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for c in id {
            if !(c.isLetter || c.isNumber) {
                if !current.isEmpty { parts.append(current.lowercased()); current = "" }
            } else if c.isUppercase, let last = current.last, last.isLowercase {
                parts.append(current.lowercased())
                current = String(c)
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { parts.append(current.lowercased()) }
        return parts
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        let pattern = "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: word) + "($|[^a-z0-9])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
