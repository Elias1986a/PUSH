import SwiftUI
import AppKit

/// The card that sits on System Settings and hands the user PUSH to drag into
/// a permission list.
///
/// Dressed as PUSH's hardware, not as a system sheet: a black slab like the
/// notch tab, the app chip outlined in the same acid green as
/// `NotchEdgePulse`, and an arrow that nudges up toward the list. Always dark,
/// for the same reason the tab is — it is a piece of PUSH, not of the window
/// it sits on.
struct PermissionGuideCard: View {
    let permissionTitle: String
    let bundleURL: URL
    let onClose: () -> Void

    static let size = CGSize(width: 470, height: 92)

    private let acid = NotchEdgePulse.Tuning.defaultColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            chip
                .overlay(BundleDragSource(url: bundleURL, image: { chipImage }))
                .accessibilityLabel("PUSHTYPE. Drag into the list above.")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    nudgingArrow
                    Text("Drag PUSHTYPE into the list above")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("That turns on \(permissionTitle). If PUSHTYPE is already listed, just switch it on.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 34)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { closeButton }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Pieces

    /// What gets dragged. Looks like a row in the list it is headed for, so the
    /// gesture explains itself.
    private var chip: some View {
        HStack(spacing: 9) {
            AppIconImage(size: 30)
            Text("PUSHTYPE")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.11)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(acid.opacity(0.85), lineWidth: 1.5)
        )
    }

    /// The chip as an image, used as the drag image so what moves under the
    /// cursor is exactly what was picked up.
    @MainActor
    private var chipImage: NSImage? {
        let renderer = ImageRenderer(content: chip.environment(\.colorScheme, .dark))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    private var nudgingArrow: some View {
        let arrow = Image(systemName: "arrow.up")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(acid)
        return Group {
            if reduceMotion {
                arrow
            } else {
                TimelineView(.animation) { context in
                    // Up and back once a second and a half: enough to point,
                    // not enough to nag.
                    let t = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.5) / 1.5
                    arrow.offset(y: -3 * sin(t * .pi))
                }
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Close")
    }
}

/// A transparent layer over the chip that starts an AppKit drag of PUSH's own
/// bundle.
///
/// AppKit rather than SwiftUI's `onDrag`: System Settings wants a plain file
/// URL on the pasteboard, and `NSURL` as the pasteboard writer gives it exactly
/// that — the same thing it gets when you drag the app in from Finder — so the
/// grant lands on this bundle's identity.
private struct BundleDragSource: NSViewRepresentable {
    let url: URL
    let image: @MainActor () -> NSImage?

    func makeNSView(context: Context) -> BundleDragView {
        BundleDragView(url: url, image: image)
    }

    func updateNSView(_ view: BundleDragView, context: Context) {}
}

final class BundleDragView: NSView, NSDraggingSource {
    private let url: URL
    private let image: @MainActor () -> NSImage?

    init(url: URL, image: @escaping @MainActor () -> NSImage?) {
        self.url = url
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The card's panel never becomes key, so the first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let picture = image() ?? NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(bounds, contents: picture)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

#if DEBUG
#Preview("Permission guide") {
    PermissionGuideCard(permissionTitle: "Accessibility",
                        bundleURL: URL(fileURLWithPath: "/Applications/PUSH.app"),
                        onClose: {})
        .padding()
}
#endif
