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
        let range: Range<String.Index>
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
                let text = String(script[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(Line(text: text, range: range))
            }
            start += count
        }

        self.lines = result
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
