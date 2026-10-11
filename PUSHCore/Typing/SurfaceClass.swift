/// What kind of place the user is typing into, from the frontmost app's bundle
/// id. Decides the surface line's `Format:` and whether there is one at all
/// (code editors and terminals get none).
public enum SurfaceClass: String, Sendable, Equatable {
    case email, chat, browser, code, terminal, other

    /// An id matches an entry when it equals it or continues it with a
    /// component (`com.google.chrome` matches `com.google.chrome.canary`).
    /// Entries ending in "." match any app under that vendor.
    public static func classify(bundleID: String?) -> SurfaceClass {
        guard let id = bundleID?.lowercased() else { return .other }
        for (surface, ids) in table {
            for entry in ids {
                if entry.hasSuffix(".") ? id.hasPrefix(entry) : (id == entry || id.hasPrefix(entry + ".")) {
                    return surface
                }
            }
        }
        return .other
    }

    // Our own lists, lowercase.
    private static let table: [(SurfaceClass, [String])] = [
        (.email, [
            "com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac",
            "com.superhuman.electron", "com.mimestream.mimestream",
        ]),
        (.chat, [
            "com.tinyspeck.slackmacgap", "com.microsoft.teams", "com.microsoft.teams2",
            "com.hnc.discord", "com.apple.mobilesms", "net.whatsapp.whatsapp",
            "desktop.whatsapp", "ru.keepcoder.telegram", "org.telegram.desktop",
            "org.whispersystems.signal-desktop",
        ]),
        (.browser, [
            "com.apple.safari", "com.google.chrome", "company.thebrowser.browser",
            "company.thebrowser.dia", "com.brave.browser", "com.microsoft.edgemac",
            "org.mozilla.firefox", "app.zen-browser.zen", "com.kagi.kagimacos",
        ]),
        (.code, [
            "com.apple.dt.xcode", "com.microsoft.vscode", "com.todesktop.230313mzl4w4u92",
            "dev.zed.zed", "com.jetbrains.", "com.sublimetext.", "com.panic.nova",
            "com.google.antigravity", "com.google.antigravity-ide",
        ]),
        (.terminal, [
            "com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
            "dev.warp.warp-stable", "com.github.wez.wezterm", "net.kovidgoyal.kitty",
            "org.alacritty",
        ]),
    ]
}
