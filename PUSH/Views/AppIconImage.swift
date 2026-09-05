import SwiftUI
import AppKit

/// The app's icon, with a stand-in for builds that do not have one.
///
/// `NSApp.applicationIconImage` is the right source in the shipped app: the
/// icon comes from the bundle, and reading the asset catalog through
/// `Bundle.module` instead crashes distribution builds — which is why every
/// call site here asks AppKit rather than looking the file up itself.
///
/// But `swift run` produces a bare executable with no `Info.plist` and so no
/// icon, and AppKit answers that with the generic executable placeholder: a
/// grey folder sitting in the middle of the welcome screen, which reads as a
/// missing asset rather than as a dev build. Substitute the app's own menu bar
/// glyph on the brand colour, so the wizard looks deliberate either way.
///
/// Keyed on the bundle identifier because that is the thing actually missing —
/// a real `.app` always has one, and it is exactly the condition under which
/// AppKit has no icon to give.
struct AppIconImage: View {
    let size: CGFloat

    /// The pill's pulse colour, shared with `PillPositionThumbnail`.
    private static let pulse = Color(red: 0.69, green: 1.0, blue: 0.0)

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    var body: some View {
        if isBundled {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.16), Color(white: 0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Image(systemName: "music.mic")
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(Self.pulse)
                )
                .frame(width: size, height: size)
                .accessibilityLabel("PUSH")
        }
    }
}
