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
    case nemotronMultilingual = "nemotron-multilingual"
    case appleSpeech = "apple-speech"

    public var id: String { rawValue }

    /// The cases the picker should offer. Enum cases can't carry `@available`, so
    /// the macOS 26 engine is filtered out here — otherwise an older system would
    /// list a model that can only ever fail to load. A stale saved preference is
    /// still handled: the engine throws a legible error rather than crashing.
    ///
    /// Ordered for the settings list rather than by declaration: the
    /// recommended default leads, the other realtime engine follows, and the
    /// older and OS-managed ones come last. `allCases` order is the enum's own
    /// business and the comparison tool still relies on it.
    public static var selectable: [WhisperModel] {
        let order: [WhisperModel] = [
            .parakeetUnified, .parakeetStreaming, .nemotronMultilingual, .parakeetV2, .appleSpeech
        ]
        return order.filter { model in
            switch model.engineType {
            case .appleSpeech:
                if #available(macOS 26, *) { return AppleSpeechEngine.isSupported }
                return false
            case .parakeet, .parakeetUnified, .parakeetStreaming, .nemotronMultilingual:
                return true
            }
        }
    }

    public var displayName: String {
        switch self {
        case .parakeetV2: return "Parakeet TDT v2 — Smallest"
        case .parakeetUnified: return "Parakeet Unified — Most accurate and fastest"
        case .parakeetStreaming: return "Parakeet Streaming — Visualize as you talk"
        case .nemotronMultilingual: return "Nemotron Multilingual — Other languages"
        case .appleSpeech: return "Apple Speech — No download"
        }
    }

    /// The model's name on its own.
    ///
    /// `displayName` carries a trailing "— Most accurate and fastest" because it
    /// had to sell the model from inside a one-line popup button. The settings
    /// list shows description and size in their own rows, so the name can just
    /// be the name — and this is also what belongs in a status message, where
    /// the sales pitch read as noise ("Loading Parakeet Unified — Most accurate
    /// and fastest…").
    public var shortName: String {
        switch self {
        case .parakeetV2: return "Parakeet TDT v2"
        case .parakeetUnified: return "Parakeet Unified"
        case .parakeetStreaming: return "Parakeet Streaming"
        case .nemotronMultilingual: return "Nemotron Multilingual"
        case .appleSpeech: return "Apple Speech"
        }
    }

    /// Short qualifier shown beside the name, where one earns its place.
    public var badge: String? {
        switch self {
        case .parakeetUnified: return "Recommended"
        case .appleSpeech: return "macOS 26"
        case .nemotronMultilingual: return "Multilingual"
        case .parakeetV2, .parakeetStreaming: return nil
        }
    }

    /// Approximate on-disk cost, for the settings list. Matches the figures
    /// `modelDescription` quotes and the progress estimates in the download.
    public var downloadSizeLabel: String {
        switch self {
        case .parakeetV2: return "400 MB"
        case .parakeetUnified, .parakeetStreaming, .nemotronMultilingual: return "600 MB"
        case .appleSpeech: return "No download"
        }
    }

    public var modelDescription: String {
        switch self {
        case .parakeetV2:
            return "Older English model, smaller download."
        case .parakeetUnified:
            return "Highest accuracy. Transcribes after you release, so longer takes wait longer."
        case .parakeetStreaming:
            return "Transcribes while you speak, so text lands instantly however long you talk."
        case .nemotronMultilingual:
            return "Streams like Parakeet Streaming, in the language you pick. Downloads one model per language group."
        case .appleSpeech:
            return "Built into macOS — nothing to download, and the system keeps it updated. Punctuates as it goes."
        }
    }

    /// The engine type used by this model
    public var engineType: EngineType {
        switch self {
        case .parakeetV2: return .parakeet
        case .parakeetUnified: return .parakeetUnified
        case .parakeetStreaming: return .parakeetStreaming
        case .nemotronMultilingual: return .nemotronMultilingual
        case .appleSpeech: return .appleSpeech
        }
    }

    /// Whether this engine takes an explicit language, and so earns a picker in
    /// Settings. The English engines never do — they are English-only by
    /// construction (the HuggingFace repos are literally `-en-`), and Parakeet
    /// TDT v3 is excluded on purpose: its `language:` parameter is a *script*
    /// filter (Latin/Cyrillic/Greek), so it cannot tell Spanish from French and
    /// a per-language picker for it would be decorative.
    public var supportsLanguageSelection: Bool {
        switch self {
        case .nemotronMultilingual, .appleSpeech: return true
        case .parakeetV2, .parakeetUnified, .parakeetStreaming: return false
        }
    }

    /// Where this engine's chosen language is persisted.
    ///
    /// Per engine, not global: each supports a different set of languages, and
    /// one shared key would seat an unsupported language the moment the user
    /// switched engines.
    ///
    /// It lives here rather than beside the app's other `UserDefaultsKeys`
    /// because the app is not the only reader — `compare/` is a separate
    /// SwiftPM package that has no `AppState` and still has to benchmark the
    /// engine in the language the user actually picked. Two hand-written copies
    /// of the same string across two packages is exactly the kind of drift that
    /// silently resets a preference, so both derive it from `rawValue` here.
    public var languageDefaultsKey: String { "language.\(rawValue)" }

    /// Every remaining model produces its own punctuation, so all of them take the
    /// reduced post-processing pipeline. Kept as a property rather than folded away:
    /// the distinction is real, and a future engine may not punctuate.
    public var hasNativePunctuation: Bool {
        switch self {
        case .parakeetV2, .parakeetUnified, .parakeetStreaming, .nemotronMultilingual,
             .appleSpeech: return true
        }
    }
}

/// Engine types for model routing
public enum EngineType: Sendable {
    case parakeet
    case parakeetUnified
    case parakeetStreaming
    case nemotronMultilingual
    case appleSpeech
}
