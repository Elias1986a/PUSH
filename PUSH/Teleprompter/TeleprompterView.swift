import SwiftUI
import PUSHCore

/// The script hanging off the notch, travelling continuously past a fixed
/// reading position.
///
/// Nothing here snaps. The script's position and every line's brightness are
/// both continuous functions of a fractional line, so a line does not jump into
/// place and then sit there — it drifts up through the reading slot and dims as
/// it passes. A whole-line hop is easy to implement and unpleasant to read
/// against: the eye has to re-acquire the text on every move.
struct TeleprompterView: View {
    @ObservedObject var settings: TeleprompterState
    @ObservedObject var session: TeleprompterSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vertical inset before content starts, so the top of the panel sits
    /// behind the camera housing / menu bar strip rather than under it.
    var topInset: CGFloat

    /// One line either side of the reading slot: three rows, one line lit at a
    /// time.
    ///
    /// A deep block of runway was tried and read badly — too much text to hold
    /// while also judging whether the scroll was keeping up with you.
    ///
    /// The line above is not decoration, it is required. With continuous
    /// scrolling the read line travels upward through its slot as you speak it,
    /// so with nothing above, the line you are currently reading would be
    /// clipped by the top edge just as you finish it. That was survivable when
    /// the scroll snapped line to line and the read line sat still; it is not
    /// now that it moves.
    private static let linesAbove = 1
    private static let linesBelow = 1
    private static var visibleLines: Int { linesAbove + 1 + linesBelow }

    private var font: NSFont {
        NSFont.systemFont(ofSize: settings.size.fontSize, weight: .semibold, width: .condensed)
    }

    var body: some View {
        let layout = session.layout
        let lineHeight = settings.size.lineHeight
        // The reading position, in fractional lines. Eased in the session, so
        // this arrives already smooth.
        let position = session.isRunning ? session.displayLine : 0

        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)

            // A fixed window with the script travelling behind it.
            //
            // The offset is applied to the *content* and the clip to the window
            // that never moves. Clipping after the offset would move the clip
            // rect along with the text, and once the reader passed the last
            // slot the stack would draw above the panel and out over the menu
            // bar.
            Color.clear
                .frame(width: settings.size.width,
                       height: lineHeight * CGFloat(Self.visibleLines))
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        // Only the lines that can be seen. Building a Text for
                        // every line of the script costs the whole script on
                        // every render, grows with script length, and runs on
                        // the main actor — where a stall makes macOS disable
                        // the event tap and kill the hotkey.
                        ForEach(visibleLineRange(in: layout, at: position), id: \.self) { index in
                            Text(styled(layout.lines[index]))
                                .font(Font(font))
                                .foregroundStyle(.white)
                                .opacity(opacity(forLine: index, at: position))
                                .frame(width: settings.size.width, alignment: .leading)
                                .offset(y: CGFloat(index) * lineHeight)
                        }
                    }
                    .offset(y: (CGFloat(Self.linesAbove) - CGFloat(position)) * lineHeight)
                }
                .clipped()
                // Dissolve at the edges instead of slicing. Continuous
                // scrolling means there is always a part-line at the top and
                // bottom, and a hard cut through the middle of letterforms is
                // the most eye-catching thing on the panel — the opposite of
                // what a prompter wants. Text now arrives and leaves.
                .mask(edgeFade)
                // Interpolates between the session's 20Hz updates so the travel
                // is continuous rather than twenty steps a second. Linear on
                // purpose: a spring would overshoot text the reader is
                // mid-sentence on and then pull it back.
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.05),
                    value: position
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: settings.size.width + 32)
        .background(tabShape.fill(.black))
        // State is carried by the edge glow rather than an indicator of its
        // own: green while it is following your voice, amber once it has lost
        // you. One less thing in shot.
        .overlay(NotchEdgePulse(shape: tabShape, color: stateColor))
    }

    /// The line's text, with anything already spoken dimmed.
    ///
    /// Only the line the reader is part-way through can be split, so this is at
    /// most one `AttributedString` per frame; the lines behind and ahead fall
    /// straight through to plain text.
    private func styled(_ line: ScriptLayout.Line) -> AttributedString {
        var text = AttributedString(line.text)
        guard settings.highlightSpokenWords,
              let spoken = session.spokenThrough,
              spoken > line.trimmedRange.lowerBound
        else { return text }

        // Wholly behind the reader: the line-level fade already says so, and
        // dimming twice would black it out.
        guard spoken < line.trimmedRange.upperBound else { return text }

        // Clamped rather than trusted: the script the layout was built from and
        // the one the aligner tokenized are the same instance, but an offset
        // past the end of the drawn line would trap rather than misdraw.
        let offset = session.script.distance(from: line.trimmedRange.lowerBound, to: spoken)
        let spokenCount = min(max(offset, 0), line.text.count)
        guard spokenCount > 0 else { return text }

        let split = text.index(text.startIndex, offsetByCharacters: spokenCount)

        // Dimmed, not coloured. On camera this sits in shot, and a colour
        // change reads as decoration where a brightness change reads as
        // progress.
        text[text.startIndex..<split].foregroundColor = .white.opacity(0.45)
        return text
    }

    /// Softens the top and bottom edges of the scrolling window.
    ///
    /// Short fades: long enough to dissolve a part-line, short enough that the
    /// reading slot and the first lines of runway are never touched by it.
    private var edgeFade: LinearGradient {
        // Expressed as a fraction of a line rather than of the panel, so it
        // stays a soft edge and never reaches the reading slot whatever the
        // row count is.
        let fade = 0.36 / Double(Self.visibleLines)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var tabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 16,
            style: .continuous
        )
    }

    /// The slice of lines that can be on screen, with a spare either side so a
    /// part-scrolled line is drawn rather than popping in at the edge.
    private func visibleLineRange(in layout: ScriptLayout, at position: Double) -> Range<Int> {
        guard !layout.lines.isEmpty else { return 0..<0 }
        let anchor = Int(position.rounded(.down))
        let lower = max(0, anchor - Self.linesAbove - 1)
        let upper = min(layout.lines.count, anchor + Self.linesBelow + 2)
        return lower..<max(lower, upper)
    }

    /// Brightness as a continuous function of distance from the reading slot.
    ///
    /// Continuous is the point. Stepping opacity per whole line makes a line
    /// change brightness all at once as the reader crosses into it, which reads
    /// as a flicker; this crossfades as the text travels. Falls off faster
    /// behind than ahead — what you have already read is worth almost nothing,
    /// what is coming is worth a lot.
    private func opacity(forLine index: Int, at position: Double) -> Double {
        let distance = Double(index) - position

        // Full brightness across the whole line, not at a single point. The
        // reading position moves continuously through a line, so a falloff
        // measured from it alone would leave *no* line fully lit whenever the
        // reader is mid-line — brightness would dip and recover once per line,
        // which is a pulse rather than a scroll. The line straddling the slot
        // stays lit for its entire traverse and crossfades with the next.
        if distance >= -1, distance <= 0 { return 1.0 }

        if distance > 0 {
            return 1.0 / (1.0 + 0.55 * distance)
        }
        return 1.0 / (1.0 + 2.4 * (-distance - 1))
    }

    private var stateColor: Color {
        switch session.position.state {
        case .tracking, .idle, .adrift: return NotchEdgePulse.Tuning.defaultColor
        // Running on the timer, or it has stopped hearing you. Either way it is
        // no longer following your voice.
        case .lost: return .orange
        }
    }
}
