import AppKit
import CoreGraphics

/// The System Settings window, when System Settings is the frontmost app.
///
/// Reads window bounds from `CGWindowListCopyWindowInfo`. Bounds and owner are
/// readable without Screen Recording — only window *titles* need it, and this
/// never asks for one — so the guide costs no extra permission.
enum SettingsWindowLocator {
    static let bundleIdentifier = "com.apple.systempreferences"

    struct Snapshot: Equatable {
        /// AppKit coordinates.
        let frame: CGRect
        /// The visible frame of the screen holding most of the window.
        let visibleFrame: CGRect
    }

    static func frontmostWindow() -> Snapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == bundleIdentifier,
              let primary = NSScreen.screens.first,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let pid = app.processIdentifier
        let frames: [CGRect] = info.compactMap { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return PermissionGuideGeometry.appKitRect(fromCG: cgRect,
                                                      primaryScreenHeight: primary.frame.height)
        }
        // The main window, not a sheet or a popover: the biggest one, and big
        // enough to be a settings window at all.
        guard let frame = frames
            .filter({ $0.width > 320 && $0.height > 240 })
            .max(by: { $0.width * $0.height < $1.width * $1.height })
        else { return nil }

        let screens = NSScreen.screens
        let index = PermissionGuideGeometry.screenIndex(for: frame, screenFrames: screens.map(\.frame)) ?? 0
        return Snapshot(frame: frame, visibleFrame: screens[index].visibleFrame)
    }
}
