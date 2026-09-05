import SwiftUI
import AppKit
import PUSHCore

/// PUSH's own icon, wherever it can be found.
///
/// Two sources, in order:
///
/// 1. `NSApp.applicationIconImage` — right in the shipped app. macOS has
///    already masked and rounded it, so it matches the icon in the Dock, in
///    Finder and in the update dialog.
/// 2. The bundled `AppIcon512.png` — for `swift run`, which produces a bare
///    executable with no `Info.plist` and therefore no icon at all. AppKit
///    answers that with the generic executable placeholder: a grey folder in
///    the middle of the welcome screen, which reads as a missing asset.
///
/// Deliberately NOT `Bundle.module`, which fatal-asserts in distribution
/// builds. This walks to the resource bundle by name and falls back to
/// `Bundle.main`, the same way `SoundPlayer` finds the start chirp — a path
/// already proven in a shipped build.
struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel("PUSH")
    }

    /// Resolved once — this is a file read, and the wizard re-renders on every
    /// keystroke in its sandbox.
    private static let icon: NSImage = resolve()

    private static func resolve() -> NSImage {
        // A real .app always has a bundle identifier, and that is exactly the
        // condition under which AppKit has an icon to give.
        if Bundle.main.bundleIdentifier != nil {
            return NSApp.applicationIconImage
        }
        if let url = resourceURL(), let image = NSImage(contentsOf: url) {
            return image
        }
        PushLogger.log("AppIconImage: no bundled icon found, falling back to the system image")
        return NSApp.applicationIconImage
    }

    private static func resourceURL() -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "PUSH_PUSH", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleURL),
           let url = resourceBundle.url(forResource: "AppIcon512", withExtension: "png") {
            return url
        }
        return Bundle.main.url(forResource: "AppIcon512", withExtension: "png")
    }
}
