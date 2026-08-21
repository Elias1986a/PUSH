import Foundation

/// The models PUSH can transcribe with, and the engine each one routes to.
///
/// These live in `PUSHCore` rather than on `AppState` because the engines, the
/// post-processing chain and the comparison tool all need them, and only one of those
/// three is the app. `AppState.WhisperModel` remains a typealias for this, so every
/// existing call site reads unchanged.
///
/// The name is historical: Whisper was dropped entirely once the comparison tool made
/// the gap plain — Parakeet Unified transcribed 8.3s of audio in 0.061s against Whisper
/// Large v3 Turbo's 1.106s, with better English accuracy and no two-minute first-run
/// compile. Moonshine went at the same time; its weights only ever existed in the
/// upstream package's test resources and were never shipped, so it could not load at all.
public enum WhisperModel: String, CaseIterable, Identifiable, Sendable {
    case parakeetV2 = "parakeet-tdt-v2"
    case parakeetUnified = "parakeet-unified"
    case parakeetStreaming = "parakeet-streaming"
    case appleSpeech = "apple-speech"

    public var id: String { rawValue }

    /// The cases the picker should offer. Enum cases can't carry `@available`, so
    /// the macOS 26 engine is filtered out here — otherwise an older system would
    /// list a model that can only ever fail to load. A stale saved preference is
    /// still handled: the engine throws a legible error rather than crashing.
    public static var selectable: [WhisperModel] {
        allCases.filter { model in
            switch model.engineType {
            case .appleSpeech:
                if #available(macOS 26, *) { return AppleSpeechEngine.isSupported }
                return false
            case .parakeet, .parakeetUnified, .parakeetStreaming:
                return true
            }
        }
    }

    public var displayName: String {
        switch self {
        case .parakeetV2: return "Parakeet TDT v2 — Smallest"
        case .parakeetUnified: return "Parakeet Unified — Most accurate and fastest"
        case .parakeetStreaming: return "Parakeet Streaming — Visualize as you talk"
        case .appleSpeech: return "Apple Speech — No download"
        }
    }

    public var modelDescription: String {
        switch self {
        case .parakeetV2:
            return "Older English model, smaller download (~400 MB)."
        case .parakeetUnified:
            return "Highest accuracy. Transcribes after you release, so longer takes wait longer (~600 MB)."
        case .parakeetStreaming:
            return "Transcribes while you speak, so text lands instantly however long you talk. Same download as Unified (~600 MB)."
        case .appleSpeech:
            return "Built into macOS 26 — nothing to download, and the system keeps it updated. Punctuates as it goes."
        }
    }

    /// The engine type used by this model
    public var engineType: EngineType {
        switch self {
        case .parakeetV2: return .parakeet
        case .parakeetUnified: return .parakeetUnified
        case .parakeetStreaming: return .parakeetStreaming
        case .appleSpeech: return .appleSpeech
        }
    }

    /// Every remaining model produces its own punctuation, so all of them take the
    /// reduced post-processing pipeline. Kept as a property rather than folded away:
    /// the distinction is real, and a future engine may not punctuate.
    public var hasNativePunctuation: Bool {
        switch self {
        case .parakeetV2, .parakeetUnified, .parakeetStreaming, .appleSpeech: return true
        }
    }
}

/// Engine types for model routing
public enum EngineType: Sendable {
    case parakeet
    case parakeetUnified
    case parakeetStreaming
    case appleSpeech
}
