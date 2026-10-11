import CoreGraphics

/// Where the drag-to-grant card goes. Pure, so the coordinate flips and the
/// clamping are tested without a window server (`PermissionGuideTests`).
enum PermissionGuideGeometry {
    /// System Settings' sidebar. The card centres on the list to its right,
    /// which is where the user has to drop.
    static let sidebarWidth: CGFloat = 220
    /// Gap between the card and the bottom of the System Settings window.
    static let bottomInset: CGFloat = 16
    /// Never closer than this to a window or screen edge.
    static let margin: CGFloat = 8

    /// `CGWindowListCopyWindowInfo` reports bounds with the origin at the top
    /// left of the primary display and y growing downward; AppKit puts it at
    /// the bottom left and y grows upward. One flip against the primary
    /// display's height converts every screen, including ones above it
    /// (negative CG y).
    static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The screen holding most of `rect`, or nil when it is on none of them.
    static func screenIndex(for rect: CGRect, screenFrames: [CGRect]) -> Int? {
        let overlaps = screenFrames.enumerated().map { index, frame -> (Int, CGFloat) in
            let shared = frame.intersection(rect)
            return (index, shared.isNull ? 0 : shared.width * shared.height)
        }
        guard let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    /// Bottom of the window, centred on the content area, kept inside the
    /// window and then inside the screen — in that order, so a window hanging
    /// off the screen still gets a card the user can reach.
    static func cardOrigin(settingsFrame: CGRect, visibleFrame: CGRect, cardSize: CGSize) -> CGPoint {
        let contentMinX = settingsFrame.minX + sidebarWidth
        var x = contentMinX + (settingsFrame.maxX - contentMinX - cardSize.width) / 2
        x = min(x, settingsFrame.maxX - cardSize.width - margin)
        x = max(x, settingsFrame.minX + margin)
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - cardSize.width - margin)

        var y = settingsFrame.minY + bottomInset
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - cardSize.height - margin)
        return CGPoint(x: x, y: y)
    }
}

/// What the card should do on each check. The guide checks on a timer *and*
/// on every app activation, and focus bounces between System Settings, its
/// Touch ID sheet and PUSH while the user works — so the window is only
/// touched when the answer actually changes, or the card flickers.
enum PermissionGuideTracker {
    enum Action: Equatable { case present, move, hide, none }

    /// `settingsFrame` is nil whenever System Settings is not the frontmost app.
    static func action(settingsFrame: CGRect?, isVisible: Bool, lastFrame: CGRect?) -> Action {
        guard let settingsFrame else { return isVisible ? .hide : .none }
        guard isVisible else { return .present }
        return settingsFrame == lastFrame ? .none : .move
    }
}
