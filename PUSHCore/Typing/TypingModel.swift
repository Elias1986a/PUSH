import Foundation

/// Type's text models, chosen by the Phase 0 eval (`docs/MODELS.md`, "Type
/// models"). Base checkpoints, GGUF, all Apache-2.0, each pinned to a
/// Hugging Face revision and checked by SHA-256 after download.
public enum TypingModel: String, CaseIterable, Sendable, Identifiable {
    case recommended = "qwen3.5-2b-base"
    case best = "gemma4-e2b-base"
    /// Cotabby's "pro" tier: Gemma 4 E4B, 5.3 GB. Added 2026-10-11 for the
    /// user to compare by feel; needs a Mac with 16 GB of memory or more.
    case pro = "gemma4-e4b-base"

    public static let defaultModel: TypingModel = .recommended

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .recommended: return "Qwen3.5 2B"
        case .best: return "Gemma 4 E2B"
        case .pro: return "Gemma 4 E4B"
        }
    }

    public var repo: String {
        switch self {
        case .recommended: return "mradermacher/Qwen3.5-2B-Base-i1-GGUF"
        case .best: return "mradermacher/gemma-4-E2B-i1-GGUF"
        case .pro: return "mradermacher/gemma-4-E4B-i1-GGUF"
        }
    }

    public var file: String {
        switch self {
        case .recommended: return "Qwen3.5-2B-Base.i1-Q4_K_M.gguf"
        case .best: return "gemma-4-E2B.i1-Q4_K_M.gguf"
        case .pro: return "gemma-4-E4B.i1-Q4_K_M.gguf"
        }
    }

    /// The repository commit the file is fetched from — never a branch, so the
    /// bytes cannot change under the checksum.
    public var revision: String {
        switch self {
        case .recommended: return "209c5e51cc8ceee9b70facbcf36c57d7968ba543"
        case .best: return "a9bf638e53783fc93778f357cc5c672eab5393b1"
        case .pro: return "8d1efb45cd65f46a70ac918584e2f0244117465f"
        }
    }

    public var bytes: Int64 {
        switch self {
        case .recommended: return 1_274_397_056
        case .best: return 3_427_862_240
        case .pro: return 5_335_274_240
        }
    }

    public var sha256: String {
        switch self {
        case .recommended: return "e3daa3f6e5ed8de264fc6e4128713ae1eb0c2649ad69b83f97bfc6a6ddca3da8"
        case .best: return "3cc0e9c2b4bbffea7f3f6cfe1ffd1591f4dafe02c43f78952f1142a24172df65"
        case .pro: return "687f4cce47eac6ccfc595fd9517215fb964e5e5be17d4774b25b8add401d6d3c"
        }
    }

    public var licence: String { "Apache-2.0" }

    /// The longest length preset this model handles well (Phase 0 eval).
    public var maxLength: LengthPreset {
        switch self {
        case .recommended: return .medium
        case .best, .pro: return .long
        }
    }

    /// Below this much memory the model would crowd out everything else.
    public var minimumMemory: UInt64 {
        self == .pro ? 16 << 30 : 0
    }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")!
    }
}

/// How long a suggestion may run, as a word range. The model stops at a
/// natural break inside the range, otherwise at its top (Task 4.6).
public enum LengthPreset: String, CaseIterable, Sendable, Comparable {
    case tiny, short, medium, long

    public static let defaultPreset: LengthPreset = .short

    public var words: ClosedRange<Int> {
        switch self {
        case .tiny: return 1...3
        case .short: return 4...7
        case .medium: return 8...12
        case .long: return 12...20
        }
    }

    public var label: String { "\(words.lowerBound)–\(words.upperBound) words" }

    /// Tokens to ask the model for: words run about 1.3 tokens in English;
    /// the margin lets the trim, not the token limit, decide where to stop.
    public var maxTokens: Int { words.upperBound * 2 + 4 }

    /// Cuts a suggestion to this preset. A sentence end always stops it (past
    /// the first sentence every model drifted in the Phase 0 eval); a comma or
    /// semicolon stops it once inside the range; otherwise it stops at the top.
    public func trim(_ suggestion: String) -> String {
        var count = 0
        var end = suggestion.startIndex
        var i = suggestion.startIndex
        while i < suggestion.endIndex {
            while i < suggestion.endIndex, suggestion[i].isWhitespace { i = suggestion.index(after: i) }
            guard i < suggestion.endIndex else { break }
            let start = i
            while i < suggestion.endIndex, !suggestion[i].isWhitespace { i = suggestion.index(after: i) }
            if suggestion[start..<i].contains(where: { $0.isLetter || $0.isNumber }) { count += 1 }
            end = i
            // Only the word's last character counts, so "3.5" or "4.30" never
            // reads as a sentence end.
            let last = suggestion[suggestion.index(before: i)]
            if ".!?".contains(last) { break }
            if ",;".contains(last), count >= words.lowerBound { break }
            if count >= words.upperBound { break }
        }
        return String(suggestion[..<end])
    }

    /// Switching to a smaller model brings the setting down with it.
    public func clamped(to model: TypingModel) -> LengthPreset { min(self, model.maxLength) }

    /// The presets the picker shows for a model.
    public static func offered(for model: TypingModel) -> [LengthPreset] {
        allCases.filter { $0 <= model.maxLength }
    }

    public static func < (a: LengthPreset, b: LengthPreset) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}
