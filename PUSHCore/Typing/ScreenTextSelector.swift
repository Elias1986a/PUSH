import CoreGraphics
import Foundation

/// Picks which text around the field the model sees: what sits in the
/// field's own column (the conversation above a chat box, the email above a
/// reply — not the sidebar of channel names), nearest first, then put back
/// in reading order. Coordinates are screen points; only relative positions
/// matter.
public enum ScreenTextSelector {
    public struct Item: Equatable, Sendable {
        public var text: String
        public var frame: CGRect
        public init(text: String, frame: CGRect) {
            self.text = text
            self.frame = frame
        }
    }

    public static let maximumCharacters = 1_000

    /// Web pages split a sentence into pieces at every link or bold word
    /// ("Thanks, " "Dana" " — see you Friday"): pieces side by side on one
    /// line become one item again.
    static func mergeLines(_ items: [Item]) -> [Item] {
        let ordered = items.sorted {
            abs($0.frame.midY - $1.frame.midY) > 3 ? $0.frame.midY > $1.frame.midY : $0.frame.minX < $1.frame.minX
        }
        var merged: [Item] = []
        for item in ordered {
            if let last = merged.last, abs(last.frame.midY - item.frame.midY) <= 3,
               item.frame.minX - last.frame.maxX < 14, item.frame.minX >= last.frame.minX {
                let joiner = last.text.hasSuffix(" ") || item.text.hasPrefix(" ") ? "" : " "
                merged[merged.count - 1] = Item(text: last.text + joiner + item.text, frame: last.frame.union(item.frame))
            } else {
                merged.append(item)
            }
        }
        return merged
    }

    public static func select(_ items: [Item], field: CGRect, maximumCharacters: Int = maximumCharacters) -> String? {
        let cleaned = mergeLines(items).compactMap { item -> Item? in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Single words are labels and buttons ("Send", "Today"), not content.
            guard text.split(whereSeparator: \.isWhitespace).count >= 2 || text.count >= 25 else { return nil }
            return Item(text: text, frame: item.frame)
        }
        // The field's column, widened a little; everything when that holds too little.
        let column = field.insetBy(dx: -field.width * 0.1, dy: 0)
        let inColumn = cleaned.filter { $0.frame.maxX > column.minX && $0.frame.minX < column.maxX }
        let pool = inColumn.map(\.text.count).reduce(0, +) >= 40 ? inColumn : cleaned

        func distance(_ item: Item) -> CGFloat {
            if item.frame.maxY <= field.minY { return field.minY - item.frame.maxY }      // below
            if item.frame.minY >= field.maxY { return item.frame.minY - field.maxY }      // above
            return 0
        }
        var chosen: [Item] = []
        var seen = Set<String>()
        var used = 0
        for item in pool.sorted(by: { distance($0) < distance($1) }) where !seen.contains(item.text) {
            let room = maximumCharacters - used
            guard room > 20 else { break }
            let text = item.text.count > room ? String(item.text.prefix(room)) + "…" : item.text
            chosen.append(Item(text: text, frame: item.frame))
            seen.insert(item.text)
            used += text.count + 1
        }
        guard !chosen.isEmpty else { return nil }
        // Reading order: top to bottom (larger y is higher), then left to right.
        let ordered = chosen.sorted {
            abs($0.frame.midY - $1.frame.midY) > 4 ? $0.frame.midY > $1.frame.midY : $0.frame.minX < $1.frame.minX
        }
        return ordered.map(\.text).joined(separator: "\n")
    }
}
