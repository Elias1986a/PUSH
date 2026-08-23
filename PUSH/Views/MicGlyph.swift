import AppKit

/// The menu bar microphone.
///
/// SF Symbols' `music.mic` — what this replaced — is a handheld stage mic held
/// at an angle. The app icon is a Shure 55-style broadcast mic: a trapezoidal
/// head with a horizontal grille on a short stand. Two different instruments
/// for one app, which is exactly what it looked like.
///
/// Drawn rather than picked, because SF Symbols has no vintage desk mic. Two
/// grille bars, not the three the real thing has: at 18pt three hairlines silt
/// up into a solid block and the glyph stops reading as a microphone at all.
enum MicGlyph {

    /// Template image, so macOS tints it for light/dark menu bars and for the
    /// highlighted state when the menu is open. Built once — the drawing
    /// handler re-runs per appearance on its own.
    static let menuBarImage: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // Menu bar glyphs do not run edge to edge.
            let rect = CGRect(x: side * 0.14, y: side * 0.08, width: side * 0.72, height: side * 0.84)
            NSColor.black.setFill()   // ignored for a template image; the shape is what matters
            path(in: rect).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func path(in rect: CGRect) -> NSBezierPath {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        func px(_ f: CGFloat) -> CGFloat { x + f * w }
        func py(_ f: CGFloat) -> CGFloat { y + f * h }

        let path = NSBezierPath()

        // Head: rounded top corners, gentle taper toward the neck.
        let head = NSBezierPath()
        let r: CGFloat = 0.10
        head.move(to: CGPoint(x: px(0.18), y: py(0.86)))
        head.curve(to: CGPoint(x: px(0.18 + r), y: py(0.97)),
                   controlPoint1: CGPoint(x: px(0.18), y: py(0.94)),
                   controlPoint2: CGPoint(x: px(0.18 + r * 0.4), y: py(0.97)))
        head.line(to: CGPoint(x: px(0.82 - r), y: py(0.97)))
        head.curve(to: CGPoint(x: px(0.82), y: py(0.86)),
                   controlPoint1: CGPoint(x: px(0.82 - r * 0.4), y: py(0.97)),
                   controlPoint2: CGPoint(x: px(0.82), y: py(0.94)))
        head.line(to: CGPoint(x: px(0.70), y: py(0.42)))
        head.line(to: CGPoint(x: px(0.30), y: py(0.42)))
        head.close()
        path.append(head)

        // Neck.
        path.append(NSBezierPath(rect: CGRect(
            x: px(0.45), y: py(0.20), width: w * 0.10, height: h * 0.24
        )))

        // Base.
        let base = NSBezierPath()
        base.move(to: CGPoint(x: px(0.30), y: py(0.03)))
        base.line(to: CGPoint(x: px(0.70), y: py(0.03)))
        base.line(to: CGPoint(x: px(0.62), y: py(0.20)))
        base.line(to: CGPoint(x: px(0.38), y: py(0.20)))
        base.close()
        path.append(base)

        // Grille, cut out of the head rather than drawn over it.
        for f in [0.58, 0.76] {
            path.append(NSBezierPath(rect: CGRect(
                x: px(0.31), y: py(CGFloat(f)), width: w * 0.38, height: h * 0.085
            )))
        }
        path.windingRule = .evenOdd
        return path
    }
}
