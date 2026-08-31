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

    /// Slots above and below the pinned line. Fixed at one each: three lines
    /// total, regardless of size.
    private static let linesAbove = 1
    private static let linesBelow = 1
    private static var visibleLines: Int { linesAbove + 1 + linesBelow }

    private var font: NSFont {
        NSFont.systemFont(ofSize: settings.size.fontSize, weight: .semibold, width: .condensed)
    }

    /// While running, lay out the session's own copy of the script — token
    /// ranges are `String.Index` values and mean nothing against a different
    /// instance. Idle, there is no cursor to place, so the settings text is
    /// safe to show as a preview.
    private var displayScript: String {
        session.isRunning ? session.script : settings.script
    }

    private var layout: ScriptLayout {
        ScriptLayout(script: displayScript, font: font, width: settings.size.width)
    }

    /// The display line the speaker is on.
    private func currentLine(in layout: ScriptLayout) -> Int {
        guard session.isRunning else { return 0 }
        let token = Int(session.position.cursor.rounded())
        guard let range = session.tokenRange(at: token) else { return 0 }
        return layout.lineIndex(containing: range.lowerBound)
    }

    var body: some View {
        let layout = layout
        let current = currentLine(in: layout)
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
                        ForEach(Array(layout.lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text)
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
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                style: .continuous
            )
            .fill(.black)
        )
        .overlay(alignment: .bottom) { stateBar }
    }

    /// Read line bright, the line just read dim, the line coming next in
    /// between — enough lookahead to phrase a sentence, not enough to invite
    /// the eye down the page.
    private func opacity(for index: Int, current: Int) -> Double {
        switch index - current {
        case 0: return 1.0
        case -1: return 0.35
        case 1: return 0.6
        default: return 0
        }
    }

    /// A short capsule at the bottom saying whether it is following you: acid
    /// green while it has you, amber once it is guessing.
    ///
    /// Short and centred rather than a full-width rule. This sits in shot on a
    /// talking-head take, and a bright bar spanning the notch reads as a
    /// progress meter and pulls the eye; a small mark reads as an indicator and
    /// doesn't. Inset from the bottom so the rounded corners don't clip it.
    private var stateBar: some View {
        Capsule()
            .fill(stateColor)
            .frame(width: 36, height: 3)
            .opacity(session.isRunning ? 0.9 : 0)
            .padding(.bottom, 5)
    }

    private var stateColor: Color {
        switch session.position.state {
        case .tracking: return Color(red: 0.69, green: 1.0, blue: 0.0)
        case .idle, .adrift: return Color(red: 0.69, green: 1.0, blue: 0.0).opacity(0.4)
        case .lost: return .orange
        }
    }
}
