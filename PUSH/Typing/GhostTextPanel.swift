import AppKit

/// Shows a suggestion: inline at the caret when nothing follows it on the line,
/// otherwise (or with no caret position) as a small card under the field —
/// Cotypist's "mirroring". Never takes focus, never takes a click.
/// Blue for now (user's call, 2026-10-10) so it cannot pass for typed text.
@MainActor
final class GhostTextPanel {
    static let shared = GhostTextPanel()

    enum Placement: Equatable {
        case inline(caret: CGRect)
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

    func show(_ text: String, at placement: Placement) {
        switch placement {
        case .inline(let caret):
            // Type size from the caret's height; baseline on the caret's bottom.
            let size = max(10, min(caret.height * 0.78, 40))
            label.font = .systemFont(ofSize: size)
            label.drawsBackground = false
            label.wantsLayer = false
            label.stringValue = text
            label.sizeToFit()
            let height = max(label.frame.height, caret.height)
            panel.setFrame(CGRect(x: caret.maxX, y: caret.minY, width: label.frame.width + 2, height: height),
                           display: true)
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
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
