import AppKit

/// Shows a suggestion: inline at the caret when nothing follows it on the line,
/// otherwise (or with no caret position) as a small card under the field —
/// Cotypist's "mirroring". Never takes focus, never takes a click.
/// Blue for now (user's call, 2026-10-10) so it cannot pass for typed text.
@MainActor
final class GhostTextPanel {
    static let shared = GhostTextPanel()

    enum Placement: Equatable {
        /// `field` bounds the text: a suggestion never runs past its right edge.
        case inline(caret: CGRect, field: CGRect?)
        case card(below: CGRect)
    }

    static let color = NSColor.systemBlue

    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.textColor = Self.color
        panel.contentView = label
    }

    var isVisible: Bool { panel.isVisible }

    /// Type size for a caret of this height.
    static func font(forCaret height: CGFloat) -> NSFont {
        .systemFont(ofSize: max(10, min(height * 0.78, 40)))
    }

    static func width(of text: String, caretHeight: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font(forCaret: caretHeight)]).width
    }

    /// Shows `text` and returns what is actually on screen: as many whole
    /// words as fit before the field's (or screen's) right edge. When not even
    /// one fits, it starts on the next line at the field's left edge, as the
    /// text itself would wrap. Nil when nothing fits at all.
    @discardableResult
    func show(_ text: String, at placement: Placement) -> String? {
        switch placement {
        case .inline(let caret, let field):
            let font = Self.font(forCaret: caret.height)
            let screenRight = (NSScreen.screens.first { $0.frame.intersects(caret) } ?? NSScreen.main)?
                .visibleFrame.maxX ?? .greatestFiniteMagnitude
            let right = min(field?.maxX ?? screenRight, screenRight) - 4
            var origin = CGPoint(x: caret.maxX, y: caret.minY)
            var shown = Self.fitting(text, width: right - origin.x, font: font)
            if shown == nil, let field {
                // Wrap: the next line down, at the field's left edge.
                origin = CGPoint(x: field.minX + 4, y: caret.minY - caret.height * 1.25)
                shown = Self.fitting(text.drop { $0 == " " }.description, width: right - origin.x, font: font)
            }
            guard let shown else { hide(); return nil }
            label.font = font
            label.drawsBackground = false
            label.wantsLayer = false
            label.stringValue = shown
            label.sizeToFit()
            // Centred on the caret's middle, not hung from its bottom: apps
            // report slightly different caret heights from one read to the
            // next, and a top-aligned label jumped up and down with them.
            let height = label.frame.height
            let middle = origin.y + caret.height / 2
            panel.setFrame(CGRect(x: origin.x, y: middle - height / 2, width: label.frame.width + 2, height: height),
                           display: true)
            panel.orderFrontRegardless()
            return shown
        case .card(let field):
            label.font = .systemFont(ofSize: 13)
            label.stringValue = "  " + text + "  "
            label.drawsBackground = true
            label.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            label.wantsLayer = true
            label.layer?.cornerRadius = 6
            label.sizeToFit()
            let size = CGSize(width: label.frame.width, height: label.frame.height + 6)
            panel.setFrame(CGRect(x: field.minX, y: field.minY - size.height - 4, width: size.width, height: size.height),
                           display: true)
            panel.orderFrontRegardless()
            return text
        }
    }

    /// The longest run of whole words of `text` that fits `width`.
    static func fitting(_ text: String, width: CGFloat, font: NSFont) -> String? {
        guard width > 0 else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attributes).width <= width { return text }
        // Each candidate is a prefix of the original words, spacing intact.
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        var best: String?
        for count in 1...parts.count {
            let candidate = parts.prefix(count).joined(separator: " ")
            if (candidate as NSString).size(withAttributes: attributes).width > width { break }
            if candidate.contains(where: { $0.isLetter || $0.isNumber }) { best = candidate }
        }
        return best
    }

    func hide() {
        panel.orderOut(nil)
    }
}
