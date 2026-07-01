import Foundation

/// User-defined word corrections (e.g. "Hammer" -> "Hamer") applied to transcriptions
/// after Whisper runs, to fix names/jargon Whisper consistently mishears.
@MainActor
final class CorrectionsStore: ObservableObject {
    static let shared = CorrectionsStore()

    struct Correction: Codable, Identifiable, Equatable {
        var id = UUID()
        var wrong: String
        var right: String
    }

    @Published var corrections: [Correction] = [] {
        didSet { save() }
    }

    private static let userDefaultsKey = "customDictionaryCorrections"

    private init() {
        load()
    }

    func addCorrection(wrong: String, right: String) {
        let wrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wrong.isEmpty, !right.isEmpty else { return }
        corrections.append(Correction(wrong: wrong, right: right))
    }

    func remove(_ correction: Correction) {
        corrections.removeAll { $0.id == correction.id }
    }

    /// Case-insensitive, whole-word replacement of every "wrong" with its "right" spelling.
    nonisolated static func apply(_ corrections: [Correction], to text: String) -> String {
        guard !corrections.isEmpty else { return text }

        var result = text
        for correction in corrections {
            guard !correction.wrong.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: correction.wrong) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: correction.right)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }

    // MARK: - Private

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Correction].self, from: data) else {
            return
        }
        corrections = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(corrections) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
