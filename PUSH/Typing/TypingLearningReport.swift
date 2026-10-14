import Foundation
import AppKit
import PUSHCore

/// The learning assessment: how the user types against how they talk, and
/// how much their history can help. Numbers and app names only; no text
/// from the history is ever written here.
enum TypingLearningReport {
    static func make(records: [TypingHistoryRecord]) -> String {
        let labelled = records.filter { $0.dictated != nil || $0.date >= labelStart(records) }
        let dictated = labelled.flatMap { $0.dictated ?? [] }
        let typed = labelled.map { record -> String in
            var text = record.text
            for part in record.dictated ?? [] { text = text.replacingOccurrences(of: part, with: " ") }
            return text
        }
        let all = TypingStyleStats.measure(records.map(\.text))
        let talk = TypingStyleStats.measure(dictated)
        let type = TypingStyleStats.measure(typed)
        let habits = TypingHabitsAssessment.measure(texts: records.map(\.text))
        let contexts = TypingHabits(texts: records.map(\.text)).contextCount

        let windows = Dictionary(grouping: records) { "\($0.bundleID)|\($0.windowTitle ?? "")" }
        let withSibling = records.filter { ($0.windowTitle ?? "").isEmpty == false && (windows["\($0.bundleID)|\($0.windowTitle ?? "")"]?.count ?? 0) > 1 }.count
        let apps = Dictionary(grouping: records, by: \.bundleID).mapValues(\.count).sorted { $0.value > $1.value }.prefix(6)
        let dates = records.map(\.date)

        func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "—" : String(format: "%.0f%%", Double(a) * 100 / Double(b)) }
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        func row(_ name: String, _ s: TypingStyleStats) -> String {
            "| \(name) | \(s.words) | \(f(s.wordsPerSentence)) | \(f(s.lettersPerWord)) | \(f(s.contractionsPer100Words)) | \(f(s.commasPerSentence)) | \(String(format: "%.0f%%", s.exclamationShare * 100)) | \(String(format: "%.0f%%", s.questionShare * 100)) | \(String(format: "%.0f%%", s.greetingShare * 100)) |"
        }

        var lines = ["# Learning assessment", "",
                     "Written \(Date().formatted(date: .abbreviated, time: .shortened)). Numbers only: no text from your history is in this file.", "",
                     "## Your history",
                     "- \(records.count) pieces of writing, \(all.words) words" + (dates.isEmpty ? "" : ", from \(dates.min()!.formatted(date: .abbreviated, time: .omitted)) to \(dates.max()!.formatted(date: .abbreviated, time: .omitted))"),
                     "- Apps: " + apps.map { "\(appName($0.key)) \($0.value)" }.joined(separator: ", "),
                     "- Pieces that share their window with another piece (past passages can help there): \(withSibling) of \(records.count) (\(pct(withSibling, records.count)))",
                     "- Dictations tagged since 9.1.3: \(dictated.count) (\(talk.words) words). Earlier writing mixes typing and talking and isn't split below.", "",
                     "## How you type against how you talk",
                     "| | Words | Words per sentence | Letters per word | Contractions per 100 words | Commas per sentence | Sentences with ! | Questions | Openings with a greeting |",
                     "|---|---|---|---|---|---|---|---|---|",
                     row("Typed (since 9.1.3)", type), row("Dictated (since 9.1.3)", talk), row("Everything", all), "",
                     "## Your habits",
                     "- Word contexts learned: \(contexts)",
                     "- Replaying your own writing (each fifth against habits from the rest): at \(habits.positions) word boundaries, a habit was offered \(habits.offered) times (\(pct(habits.offered, habits.positions)))",
                     "- When offered: first word right \(pct(habits.firstWordRight, habits.offered)), every word right \(pct(habits.allRight, habits.offered))", ""]
        if dictated.isEmpty {
            lines.append("_The typed-vs-dictated rows fill in as you dictate into fields where Type is on. Run this again in a week._")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Records from the first dictation tag on count as labelled.
    private static func labelStart(_ records: [TypingHistoryRecord]) -> Date {
        records.filter { $0.dictated != nil }.map(\.date).min() ?? .distantFuture
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
