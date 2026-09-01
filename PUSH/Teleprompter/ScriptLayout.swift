import AppKit
import CoreText

/// Breaks a script into display lines at a fixed column width, keeping each
/// line's range in the original text.
///
/// Done explicitly rather than letting SwiftUI wrap, because the prompter has
/// to answer "which line is the speaker on?" — and that question needs the same
/// line breaks the view is drawing, not an approximation of them.
struct ScriptLayout {

    struct Line {
        let text: String
        /// The line's span in the script, as CoreText broke it.
        let range: Range<String.Index>
        /// The span of `text` itself — `range` minus the whitespace trimmed off
        /// the ends. Character offsets into `text` are only meaningful against
        /// this, which is what word-level highlighting needs to map a token's
        /// position in the script onto a position in the drawn string.
        let trimmedRange: Range<String.Index>
    }

    let lines: [Line]

    init(script: String, font: NSFont, width: CGFloat) {
        guard !script.isEmpty, width > 0 else {
            self.lines = []
            return
        }

        let attributed = NSAttributedString(string: script, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)

        var result: [Line] = []
        var start = 0
        let length = attributed.length

        while start < length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            // A width too narrow for even one glyph would otherwise spin here.
            guard count > 0 else { break }
            let utf16Range = NSRange(location: start, length: count)
            if let range = Range(utf16Range, in: script) {
                let trimmed = Self.trimmed(range, in: script)
                result.append(Line(
                    text: String(script[trimmed]),
                    range: range,
                    trimmedRange: trimmed
                ))
            }
            start += count
        }

        self.lines = result
    }

    /// `range` with leading and trailing whitespace excluded, so the result
    /// indexes exactly the characters that get drawn.
    private static func trimmed(_ range: Range<String.Index>, in script: String) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, script[lower].isWhitespace {
            lower = script.index(after: lower)
        }
        while upper > lower {
            let previous = script.index(before: upper)
            guard script[previous].isWhitespace else { break }
            upper = previous
        }
        return lower..<upper
    }

    /// Which display line the given character index falls on.
    ///
    /// Clamped rather than optional: the caller always needs a line to show,
    /// and "past the end" means the last one.
    func lineIndex(containing index: String.Index) -> Int {
        for (i, line) in lines.enumerated() where index < line.range.upperBound {
            return i
        }
        return max(lines.count - 1, 0)
    }
}
