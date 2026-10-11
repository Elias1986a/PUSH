import Foundation

/// The one-line description of where the user is typing, placed before their
/// text in the prompt: `Format: chat; App: Slack; Title: #design; Field: Message #design.`
public enum SurfaceLine {
    static let titleCap = 80
    static let placeholderCap = 60

    /// Nil for code editors and terminals (app metadata pushes a small model
    /// toward code), and for `.other` when there is nothing beyond the app name.
    public static func render(surface: SurfaceClass, appName: String?, windowTitle: String?,
                              url: String?, placeholder: String?) -> String? {
        let format: String
        switch surface {
        case .code, .terminal: return nil
        case .email: format = "email"
        case .chat: format = "chat"
        case .browser: format = "web text"
        case .other: format = "text"
        }

        let app = appName.map(clean) ?? ""
        let title = windowTitle.map { cap(stripAppSuffix(clean($0), app: app), titleCap) } ?? ""
        let field = placeholder.map { cap(clean($0), placeholderCap) } ?? ""
        let domain = url.flatMap(host) ?? ""

        if surface == .other && title.isEmpty && field.isEmpty && domain.isEmpty { return nil }

        var parts = ["Format: \(format)"]
        if !app.isEmpty { parts.append("App: \(app)") }
        if !domain.isEmpty { parts.append("Domain: \(domain)") }
        if !title.isEmpty, title.lowercased() != app.lowercased() { parts.append("Title: \(title)") }
        if !field.isEmpty { parts.append("Field: \(field)") }
        return parts.joined(separator: "; ") + "."
    }

    /// Control characters and double quotes out, whitespace runs to one space.
    static func clean(_ text: String) -> String {
        let kept = text.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || scalar == "\"" ? " " : Character(scalar)
        }
        return String(kept).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// "#design - Slack" → "#design", for " - ", " — " and " – ", any case.
    static func stripAppSuffix(_ title: String, app: String) -> String {
        guard !app.isEmpty else { return title }
        for dash in [" - ", " — ", " – "] {
            let suffix = dash + app
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                return String(title.dropLast(suffix.count))
            }
        }
        return title
    }

    static func cap(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) : text
    }

    /// Host only: no scheme, path, query or `www.`.
    static func host(_ url: String) -> String? {
        guard var host = URL(string: url)?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
