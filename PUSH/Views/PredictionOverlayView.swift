import SwiftUI
import AppKit

/// Floating overlay that shows autocomplete predictions near the cursor
@MainActor
final class PredictionOverlayController {
    static let shared = PredictionOverlayController()

    private var overlayWindow: NSWindow?
    private var hostingController: NSHostingController<PredictionOverlayContent>?
    private var currentText = ""

    private init() {}

    // MARK: - Public API

    func show(prediction: String) {
        guard !prediction.isEmpty else {
            hide()
            return
        }

        currentText = prediction

        if overlayWindow == nil {
            createWindow()
        }

        hostingController?.rootView = PredictionOverlayContent(text: prediction)
        positionAtCursor()
        overlayWindow?.orderFront(nil)
    }

    func hide() {
        currentText = ""
        overlayWindow?.orderOut(nil)
    }

    func isVisible() -> Bool {
        return overlayWindow?.isVisible ?? false
    }

    // MARK: - Private

    private func createWindow() {
        let content = PredictionOverlayContent(text: "")
        let hosting = NSHostingController(rootView: content)

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.borderless]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true

        self.overlayWindow = window
        self.hostingController = hosting
    }

    private func positionAtCursor() {
        guard let window = overlayWindow else { return }

        // Try to get cursor position from Accessibility API
        if let cursorPos = getCursorPosition() {
            // Position just below and to the right of the cursor
            let x = cursorPos.x
            let y = cursorPos.y - 30 // Below the text line
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            // Fallback: use mouse position
            let mousePos = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: mousePos.x + 10, y: mousePos.y - 30))
        }

        // Resize to fit content
        if let hosting = hostingController {
            hosting.view.layoutSubtreeIfNeeded()
            let size = hosting.view.fittingSize
            window.setContentSize(NSSize(
                width: min(size.width + 16, 400),
                height: size.height + 8
            ))
        }
    }

    private func getCursorPosition() -> NSPoint? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success else { return nil }

        // Get selected text range to find cursor position
        var selectedRange: AnyObject?
        AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        guard let rangeValue = selectedRange else { return nil }

        // Get bounds of the selected text range
        var bounds: AnyObject?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            focusedElement as! AXUIElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &bounds
        )

        guard boundsResult == .success, let boundsValue = bounds else { return nil }

        var rect = CGRect.zero
        if AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) {
            // Convert from screen coordinates (top-left origin) to Cocoa (bottom-left origin)
            if let screen = NSScreen.main {
                let screenHeight = screen.frame.height
                return NSPoint(x: rect.origin.x, y: screenHeight - rect.origin.y - rect.height)
            }
        }

        return nil
    }
}

// MARK: - SwiftUI View

struct PredictionOverlayContent: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.gray.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            )
    }
}
