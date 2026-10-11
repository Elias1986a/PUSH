/// Fits prompt sections into a character budget by priority. The caret text
/// has the top priority and keeps its end, so the words nearest the caret are
/// the last to go.
public enum PromptBudget {
    public enum Keep: Sendable { case start, end }

    public struct Section: Sendable, Equatable {
        public var name: String
        public var text: String
        public var priority: Int
        public var keep: Keep
        public var cap: Int?
        /// Dropped entirely rather than cut (a quotation, a set of examples).
        public var allOrNothing: Bool

        public init(name: String, text: String, priority: Int, keep: Keep,
                    cap: Int? = nil, allOrNothing: Bool = false) {
            self.name = name
            self.text = text
            self.priority = priority
            self.keep = keep
            self.cap = cap
            self.allOrNothing = allOrNothing
        }
    }

    /// Sections are joined by one separator (a newline), which costs one
    /// character between each pair. Returned in input order; sections that
    /// end up empty are left out.
    public static func fit(_ sections: [Section], total: Int) -> [Section] {
        var remaining = total
        var kept: [Int: Section] = [:]
        // Highest priority first; ties keep input order.
        let order = sections.indices.sorted { a, b in
            sections[a].priority != sections[b].priority ? sections[a].priority > sections[b].priority : a < b
        }
        for i in order {
            let section = sections[i]
            guard !section.text.isEmpty else { continue }
            let separator = kept.isEmpty ? 0 : 1
            let allowance = min(section.cap ?? .max, remaining - separator)
            guard allowance > 0 else { continue }
            let text: String
            if section.allOrNothing {
                guard section.text.count <= allowance else { continue }
                text = section.text
            } else {
                text = section.keep == .start
                    ? String(section.text.prefix(allowance))
                    : String(section.text.suffix(allowance))
            }
            remaining -= text.count + separator
            var trimmed = section
            trimmed.text = text
            kept[i] = trimmed
        }
        return sections.indices.compactMap { kept[$0] }
    }
}
