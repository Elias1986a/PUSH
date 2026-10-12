import AppKit

/// A small chip just outside the field being typed in, on the caret's line,
/// saying suggestions are on here — Cotypist and Cotabby both show one.
/// Never takes focus or clicks. Settings → Typing can turn it off.
@MainActor
final class TypeIndicatorPanel {
    static let shared = TypeIndicatorPanel()
    static let side: CGFloat = 16
    private static let gap: CGFloat = 5

    private let panel: NSPanel
    private let chip = NSView()
    private let glyph = NSImageView()

    private init() {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: Self.side, height: Self.side),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A solid dark chip with a hairline edge reads on any background — a
        // light wallpaper, a dark terminal. Filled with the suggestion color,
        // gray (semi-transparent by design) washed out into a pale square.
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 4.5
        chip.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.94).cgColor
        chip.layer?.borderColor = NSColor(white: 1, alpha: 0.18).cgColor
        chip.layer?.borderWidth = 0.5
        chip.frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        glyph.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Suggestions on")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        glyph.frame = chip.bounds
        chip.addSubview(glyph)
        panel.contentView = chip
    }

    /// `color`: the suggestion color, which tints the symbol (gray as a soft
    /// light gray, so it shows on the dark chip).
    func show(field: CGRect, caret: CGRect?, color: SuggestionColor) {
        let screen = (NSScreen.screens.first { $0.frame.intersects(field) } ?? NSScreen.main)?.visibleFrame ?? field
        glyph.contentTintColor = color == .preset(.gray) ? NSColor(white: 0.82, alpha: 1) : color.color
        panel.setFrame(Self.frame(field: field, caret: caret, screen: screen), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Left of the field, on the caret's line (a document is one tall field,
    /// so its middle can be far from where the user types); right of it when
    /// the field touches the screen's left edge. AppKit coordinates.
    static func frame(field: CGRect, caret: CGRect?, screen: CGRect) -> CGRect {
        var x = field.minX - side - gap
        if x < screen.minX + 2 { x = field.maxX + gap }
        let y: CGFloat
        if let caret, caret.height > 0 {
            y = caret.midY - side / 2
        } else if field.height <= 44 {
            y = field.midY - side / 2
        } else {
            y = field.maxY - side - 8   // no caret: the first line
        }
        return CGRect(x: x, y: y, width: side, height: side)
    }
}
