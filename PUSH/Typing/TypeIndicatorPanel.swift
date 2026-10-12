import AppKit

/// A small chip just outside the field being typed in, on the caret's line,
/// saying suggestions are on here — Cotypist and Cotabby both show one.
/// Never takes focus or clicks. Settings → Typing can turn it off.
@MainActor
final class TypeIndicatorPanel {
    static let shared = TypeIndicatorPanel()
    nonisolated static let side: CGFloat = 16
    nonisolated private static let gap: CGFloat = 5

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

    /// Shows the chip at `frame` (from `place`). `color`: the suggestion
    /// color, which tints the symbol (gray as a soft light gray, so it shows
    /// on the dark chip).
    func show(at frame: CGRect, color: SuggestionColor) {
        glyph.contentTintColor = color == .preset(.gray) ? NSColor(white: 0.82, alpha: 1) : color.color
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    /// Where the chip goes: the first spot, in order, with nothing to click
    /// under it — left of the field on the caret's line, right of it, above
    /// its top-left corner, below it. Chat boxes keep an attach "+" just left
    /// of the text (user screenshot, 2026-10-11), and the chip sat on it.
    /// Nil when every spot is taken: better no chip than a covered button.
    /// Only the app being typed in counts (`pid`): a window of another app
    /// behind it — Safari's links beside a Terminal window — is not what the
    /// chip could get in the way of. Accessibility hit tests: call **off the
    /// main thread**.
    nonisolated static func place(field: CGRect, caret: CGRect?, screen: CGRect, pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        return candidates(field: field, caret: caret, screen: screen).first { isClear($0, in: app) }
    }

    /// The spots `place` tries, on screen, in order. AppKit coordinates.
    nonisolated static func candidates(field: CGRect, caret: CGRect?, screen: CGRect) -> [CGRect] {
        let y: CGFloat
        if let caret, caret.height > 0 {
            y = caret.midY - side / 2
        } else if field.height <= 44 {
            y = field.midY - side / 2
        } else {
            y = field.maxY - side - 8   // no caret: the first line
        }
        return [
            CGRect(x: field.minX - side - gap, y: y, width: side, height: side),
            CGRect(x: field.maxX + gap, y: y, width: side, height: side),
            CGRect(x: field.minX, y: field.maxY + gap, width: side, height: side),
            CGRect(x: field.minX, y: field.minY - side - gap, width: side, height: side),
        ].filter { screen.insetBy(dx: 2, dy: 2).contains($0) }
    }

    /// Nothing in `app` a person would click under `rect`.
    nonisolated private static func isClear(_ rect: CGRect, in app: AXUIElement) -> Bool {
        let height = CGDisplayBounds(CGMainDisplayID()).height   // AppKit → Accessibility (top-left) coordinates
        for point in [CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: rect.minX + 2, y: rect.midY),
                      CGPoint(x: rect.maxX - 2, y: rect.midY)] {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(height - point.y), &hit) == .success,
                  let hit else { continue }
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &role)
            if let role = role as? String, interactiveRoles.contains(role) { return false }
        }
        return true
    }

    private nonisolated static let interactiveRoles: Set<String> = [
        "AXButton", "AXLink", "AXPopUpButton", "AXMenuButton", "AXCheckBox", "AXRadioButton",
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSlider", "AXIncrementor",
        "AXDisclosureTriangle", "AXSegmentedControl",
    ]

    func hide() {
        panel.orderOut(nil)
    }


}
