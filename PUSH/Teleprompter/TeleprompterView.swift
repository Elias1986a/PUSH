import SwiftUI
import PUSHCore

/// Three lines of script hanging off the notch, with the line you are reading
/// pinned at a constant height.
///
/// The pinned slot is the whole design: text flows up *through* it and the slot
/// never moves, so your eyes hold one position and the shot reads as you looking
/// at the lens rather than scanning a page.
struct TeleprompterView: View {
    @ObservedObject var settings: TeleprompterState
    @ObservedObject var session: TeleprompterSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vertical inset before content starts, so the top of the panel sits
    /// behind the camera housing / menu bar strip rather than under it.
    var topInset: CGFloat

    /// Slots above and below the pinned line. Three lines total either way,
    /// regardless of size.
    ///
    /// Nothing above: on a take, knowing what is coming is worth more than
    /// seeing the line you just finished. Spending both spare slots on
    /// lookahead gives a full clause of runway to phrase against, where one
    /// line ahead only gets you to the next few words.
    private static let linesAbove = 0
    private static let linesBelow = 2
    private static var visibleLines: Int { linesAbove + 1 + linesBelow }

    private var font: NSFont {
        NSFont.systemFont(ofSize: settings.size.fontSize, weight: .semibold, width: .condensed)
    }

    var body: some View {
        // Both the line breaks and the current line come from the session, so
        // the text drawn here and the line the arrow keys count against can
        // never disagree.
        let layout = session.layout
        let current = session.currentLine
        let lineHeight = settings.size.lineHeight

        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)

            // A fixed three-line window with the script sliding behind it.
            //
            // The order matters: the offset is applied to the *content*, and
            // the clip to the window that never moves. Clipping after the
            // offset would move the clip rect along with the text, and once the
            // cursor passed the third line the stack would draw above the panel
            // and out over the menu bar.
            Color.clear
                .frame(width: settings.size.width,
                       height: lineHeight * CGFloat(Self.visibleLines))
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        // Only the lines that can be seen. Building a Text for
                        // every line of the script and hiding all but three
                        // costs the whole script on every one of the 20 renders
                        // a second — work that grows with script length, on the
                        // main actor, in an app where blocking the main thread
                        // makes macOS disable the event tap and silently kill
                        // the hotkey. Slicing keeps a render constant-cost.
                        ForEach(visibleLineRange(in: layout, current: current), id: \.self) { index in
                            Text(layout.lines[index].text)
                                .font(Font(font))
                                .foregroundStyle(.white)
                                .opacity(opacity(for: index, current: current))
                                .frame(width: settings.size.width, alignment: .leading)
                                .offset(y: CGFloat(index) * lineHeight)
                        }
                    }
                    // Pin the current line into the second slot: the script
                    // slides, the slot does not.
                    .offset(y: CGFloat(Self.linesAbove - current) * lineHeight)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85),
                        value: current
                    )
                }
                .clipped()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: settings.size.width + 32)
        .background(tabShape.fill(.black))
        // State is carried by the edge glow rather than an indicator of its
        // own: green while it is following your voice, amber once it has lost
        // you and is guessing. One less thing in shot.
        .overlay(NotchEdgePulse(shape: tabShape, color: stateColor))
    }

    private var tabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 16,
            style: .continuous
        )
    }

    /// The slice of lines that can actually be on screen: the pinned line and
    /// its one neighbour either side, clamped to the script.
    private func visibleLineRange(in layout: ScriptLayout, current: Int) -> Range<Int> {
        guard !layout.lines.isEmpty else { return 0..<0 }
        let lower = max(0, current - Self.linesAbove)
        let upper = min(layout.lines.count, current + Self.linesBelow + 1)
        return lower..<max(lower, upper)
    }

    /// Read line bright, then falling away with distance. The gradient is the
    /// point: it says which line to read without a highlight or a caret, and it
    /// keeps the eye from being pulled to the bottom of the block.
    private func opacity(for index: Int, current: Int) -> Double {
        switch index - current {
        case 0: return 1.0
        case 1: return 0.6
        case 2: return 0.38
        default: return 0
        }
    }

    private var stateColor: Color {
        switch session.position.state {
        case .tracking, .idle, .adrift: return NotchEdgePulse.Tuning.defaultColor
        // Running on the timer, or drifting because it lost the thread. Either
        // way it is guessing where you are rather than hearing it.
        case .lost: return .orange
        }
    }
}
