import Foundation

/// The models PUSH can transcribe with, and the engine each one routes to.
///
/// These live in `PUSHCore` rather than on `AppState` because the engines, the
/// post-processing chain and the comparison tool all need them, and only one of those
/// three is the app. `WhisperModel` remains a typealias for this, so every
/// existing call site reads unchanged.

public enum WhisperModel: String, CaseIterable, Identifiable, Sendable {
    case base = "ggml-base.en"
    case small = "ggml-small.en"
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case moonshineTiny = "moonshine-tiny"
    case parakeetV2 = "parakeet-tdt-v2"
    case parakeetUnified = "parakeet-unified"
    case parakeetStreaming = "parakeet-streaming"
    case appleSpeech = "apple-speech"
    // case qwen3ASR = "qwen3-asr" // TODO: Re-enable once MLX metallib bundling is resolved.
    // Spike finding (claude/mlx-bundling-spike, now deleted): the GPU test
    // passed and the metallib loads fine — it lives at
    // Contents/Resources/default.metallib inside mlx-swift_Cmlx.bundle, not
    // at the bundle's top level. Prime suspect for the .app failure is that
    // build_distribution.sh copies the nested *.bundle into Resources but
    // never code-signs it. Start there if resuming.

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
            case .whisperKit, .moonshine, .parakeet, .parakeetUnified, .parakeetStreaming:
                return true
            }
        }
    }

    public var displayName: String {
        switch self {
        case .base: return "Whisper Base"
        case .small: return "Whisper Small"
        case .whisperLargeV3Turbo: return "Whisper Large V3 Turbo"
        case .moonshineTiny: return "Moonshine Tiny"
        case .parakeetV2: return "Parakeet TDT v2 — Smallest download"
        case .parakeetUnified: return "Parakeet Unified — Most accurate"
        case .parakeetStreaming: return "Parakeet Streaming — Fastest & balanced"
        case .appleSpeech: return "Apple Speech — No download"
        }
    }

    public var modelDescription: String {
        switch self {
        case .base: return "Fastest WhisperKit model, lower accuracy (~150 MB)"
        case .small: return "Good balance of speed and accuracy (~250 MB)"
        case .whisperLargeV3Turbo: return "High accuracy, 99+ languages (~632 MB)"
        case .moonshineTiny: return "Ultra-fast, optimized for short speech (~45 MB)"
        case .parakeetV2: return "Older English model, smaller download (~400 MB)."
        case .parakeetUnified: return "Highest accuracy. Transcribes after you release, so longer takes wait longer (~600 MB)."
        case .parakeetStreaming: return "Transcribes while you speak, so text lands instantly however long you talk. Same download as Unified (~600 MB)."
        case .appleSpeech: return "Built into macOS 26 — nothing to download, and the system keeps it updated. Punctuates as it goes."
        }
    }

    /// The engine type used by this model
    public var engineType: EngineType {
        switch self {
        case .base, .small, .whisperLargeV3Turbo:
            return .whisperKit
        case .moonshineTiny:
            return .moonshine
        case .parakeetV2:
            return .parakeet
        case .parakeetUnified:
            return .parakeetUnified
        case .parakeetStreaming:
            return .parakeetStreaming
        case .appleSpeech:
            return .appleSpeech
        }
    }

    /// Whether this model uses the Moonshine engine instead of WhisperKit
    public var isMoonshine: Bool { engineType == .moonshine }

    /// Whether this model produces high-quality native punctuation (skip punctuation post-processing)
    public var hasNativePunctuation: Bool {
        switch self {
        case .parakeetV2, .parakeetUnified, .parakeetStreaming, .appleSpeech: return true
        default: return false
        }
    }
}

/// Engine types for model routing
public enum EngineType: Sendable {
    case whisperKit
    case moonshine
    case parakeet
    case parakeetUnified
    case parakeetStreaming
    case appleSpeech
}
