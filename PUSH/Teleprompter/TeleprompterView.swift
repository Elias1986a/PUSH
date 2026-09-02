import SwiftUI
import PUSHCore

/// The script hanging off the notch, travelling continuously past a fixed
/// reading position.
///
/// Two different granularities, on purpose. The script's *position* is a
/// continuous function of a fractional line, so the text travels rather than
/// hopping — a hop makes the eye re-acquire the text on every move. Its
/// *brightness* is not: the line being read is lit as a whole and hands over to
/// the next in one crossfade. Sliding brightness between lines tracks words
/// rather than the line you are on, which is unreadable however smooth it is.
struct TeleprompterView: View {
    @ObservedObject var settings: TeleprompterState
    @ObservedObject var session: TeleprompterSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vertical inset before content starts, so the top of the panel sits
    /// behind the camera housing / menu bar strip rather than under it.
    var topInset: CGFloat

    /// One line of context above the reading slot, four of runway below.
    ///
    /// Six rows, with exactly one line lit at a time. The two are independent:
    /// how much you can see ahead is not the same question as how much is
    /// marked as where you are, and the answer here is "plenty" and "one line".
    ///
    /// The line above is not decoration, it is required. With continuous
    /// scrolling the read line travels upward through its slot as you speak it,
    /// so with nothing above, the line you are currently reading would be
    /// clipped by the top edge just as you finish it. That was survivable when
    /// the scroll snapped line to line and the read line sat still; it is not
    /// now that it moves.
    private static let linesAbove = 1
    private static let linesBelow = 4
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
        // Whole lines, not a fraction. The scroll travels smoothly; the
        // highlight hands over from one line to the next in one go.
        let lit = session.highlightLine

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
                                .opacity(opacity(forLine: index, lit: lit))
                                .frame(width: settings.size.width, alignment: .leading)
                                .offset(y: CGFloat(index) * lineHeight)
                        }
                    }
                    .offset(y: (CGFloat(Self.linesAbove) - CGFloat(position)) * lineHeight)
                    // Crossfade the hand-over so the change of lit line is not
                    // itself a hard step.
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.18),
                        value: lit
                    )
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

    /// Brightness by whole lines from the line being read.
    ///
    /// Measured against the lit line rather than the scroll position. Driving
    /// this from the fractional position instead made brightness slide between
    /// lines as the reader crossed one — the whole line was never lit at once,
    /// and what you saw was the highlight tracking words rather than the line
    /// you were on.
    ///
    /// Falls off faster behind than ahead: what you have already read is worth
    /// almost nothing, what is coming is worth a lot.
    private func opacity(forLine index: Int, lit: Int) -> Double {
        let distance = index - lit
        if distance == 0 { return 1.0 }
        if distance > 0 {
            return 1.0 / (1.0 + 0.55 * Double(distance))
        }
        return 1.0 / (1.0 + 2.4 * Double(-distance))
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
