import Foundation

/// Type's text models, chosen by the Phase 0 eval (`docs/MODELS.md`, "Type
/// models"). Base checkpoints, GGUF, all Apache-2.0, each pinned to a
/// Hugging Face revision and checked by SHA-256 after download.
public enum TypingModel: String, CaseIterable, Sendable, Identifiable {
    case lite = "qwen3.5-0.8b-base"
    case recommended = "qwen3.5-2b-base"
    case best = "gemma4-e2b-base"

    public static let defaultModel: TypingModel = .recommended

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lite: return "Qwen3.5 0.8B"
        case .recommended: return "Qwen3.5 2B"
        case .best: return "Gemma 4 E2B"
        }
    }

    public var repo: String {
        switch self {
        case .lite: return "mradermacher/Qwen3.5-0.8B-Base-i1-GGUF"
        case .recommended: return "mradermacher/Qwen3.5-2B-Base-i1-GGUF"
        case .best: return "mradermacher/gemma-4-E2B-i1-GGUF"
        }
    }

    public var file: String {
        switch self {
        case .lite: return "Qwen3.5-0.8B-Base.i1-Q6_K.gguf"
        case .recommended: return "Qwen3.5-2B-Base.i1-Q4_K_M.gguf"
        case .best: return "gemma-4-E2B.i1-Q4_K_M.gguf"
        }
    }

    /// The repository commit the file is fetched from — never a branch, so the
    /// bytes cannot change under the checksum.
    public var revision: String {
        switch self {
        case .lite: return "0adcee13f1a32c38fdbdb93e21d57e76b5640836"
        case .recommended: return "209c5e51cc8ceee9b70facbcf36c57d7968ba543"
        case .best: return "a9bf638e53783fc93778f357cc5c672eab5393b1"
        }
    }

    public var bytes: Int64 {
        switch self {
        case .lite: return 629_744_512
        case .recommended: return 1_274_397_056
        case .best: return 3_427_862_240
        }
    }

    public var sha256: String {
        switch self {
        case .lite: return "febd85051361ccb34d0925744c819f9ae0724117e8f946a2852dd0edfa90a5a1"
        case .recommended: return "e3daa3f6e5ed8de264fc6e4128713ae1eb0c2649ad69b83f97bfc6a6ddca3da8"
        case .best: return "3cc0e9c2b4bbffea7f3f6cfe1ffd1591f4dafe02c43f78952f1142a24172df65"
        }
    }

    public var licence: String { "Apache-2.0" }

    /// The longest length preset this model handles well (Phase 0 eval).
    public var maxLength: LengthPreset {
        switch self {
        case .lite: return .short
        case .recommended: return .medium
        case .best: return .long
        }
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
