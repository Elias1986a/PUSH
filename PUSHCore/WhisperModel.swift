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
/// Apple Speech went in 8.2.0: last in every benchmark run ("one. 52 seconds" for 1.52,
/// "Prius" for Priya), and not something to put PUSH's name next to. A saved
/// "apple-speech" preference no longer decodes and launch falls back to the default.
public enum WhisperModel: String, CaseIterable, Identifiable, Sendable {
    case parakeetUnified = "parakeet-unified"
    case parakeetUltra = "parakeet-ultra"
    case parakeetStreaming = "parakeet-streaming"
    case nemotronMultilingual = "nemotron-multilingual"

    public var id: String { rawValue }

    /// The model a fresh install uses, and what launch falls back to first.
    /// Parakeet Ultra since 8.0.9: faster than Unified in real use (~0.08s vs
    /// ~0.15s on the same clip), as accurate on English, and it handles the
    /// Latin-script European languages too.
    public static let defaultModel: WhisperModel = .parakeetUltra

    /// The cases the picker should offer, ordered for the settings list rather
    /// than by declaration: the recommended default leads and the multilingual
    /// engine comes last. `allCases` order is the enum's own business and the
    /// comparison tool still relies on it.
    public static let selectable: [WhisperModel] = [
        .parakeetUltra, .parakeetUnified, .parakeetStreaming, .nemotronMultilingual
    ]

    public var displayName: String {
        switch self {
        case .parakeetUnified: return "Parakeet Unified — English only"
        case .parakeetUltra: return "Parakeet Ultra — English and European languages"
        case .parakeetStreaming: return "Parakeet Streaming — Visualize as you talk"
        case .nemotronMultilingual: return "Nemotron Multilingual — Other languages"
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
        case .parakeetUnified: return "Parakeet Unified"
        case .parakeetUltra: return "Parakeet Ultra"
        case .parakeetStreaming: return "Parakeet Streaming"
        case .nemotronMultilingual: return "Nemotron Multilingual"
        }
    }

    /// Short qualifier shown beside the name, where one earns its place.
    public var badge: String? {
        switch self {
        case .parakeetUltra: return "Recommended"
        case .nemotronMultilingual: return "Multilingual"
        case .parakeetUnified, .parakeetStreaming: return nil
        }
    }

    /// Approximate on-disk cost, for the settings list. Matches the figures
    /// `modelDescription` quotes and the progress estimates in the download.
    public var downloadSizeLabel: String {
        "600 MB"
    }

    public var modelDescription: String {
        switch self {
        case .parakeetUnified:
            return "English only. Very accurate; transcribes after you release, so longer takes wait longer."
        case .parakeetUltra:
            return "Fastest and most accurate. Understands English and the European languages written in the Latin alphabet — Spanish, French, German, Italian, Portuguese and more — and switches between them on its own. For other languages, use Nemotron Multilingual."
        case .parakeetStreaming:
            return "Transcribes while you speak, so text lands instantly however long you talk."
        case .nemotronMultilingual:
            return "For languages Parakeet Ultra doesn't cover — Chinese, Japanese, Arabic, Hindi, Russian, Greek and more. Streams as you speak, in the language you pick. For English and European languages like Spanish, French and German, use Parakeet Ultra."
        }
    }

    /// The engine type used by this model
    public var engineType: EngineType {
        switch self {
        case .parakeetUnified: return .parakeetUnified
        case .parakeetUltra: return .parakeetUltra
        case .parakeetStreaming: return .parakeetStreaming
        case .nemotronMultilingual: return .nemotronMultilingual
        }
    }

    /// Whether this engine takes an explicit language, and so earns a picker in
    /// Settings. The English engines never do — they are English-only by
    /// construction (the HuggingFace repos are literally `-en-`), and Parakeet
    /// TDT v3 is excluded on purpose: its `language:` parameter is a *script*
    /// filter (Latin/Cyrillic/Greek), so it cannot tell Spanish from French and
    /// a per-language picker for it would be decorative. Parakeet Ultra is
    /// v3-derived and inherits the same limitation, so it is offered as an
    /// English engine (its decoder's script filter is pinned to Latin).
    public var supportsLanguageSelection: Bool {
        switch self {
        case .nemotronMultilingual: return true
        case .parakeetUltra, .parakeetUnified, .parakeetStreaming: return false
        }
    }

    /// Whether this engine picks the language itself on each dictation, so the
    /// transcript's language has to be read from the text afterwards
    /// (`TranscriptLanguage.detect`) rather than from a setting.
    public var detectsLanguagePerUtterance: Bool {
        switch self {
        case .parakeetUltra: return true
        case .parakeetUnified, .parakeetStreaming, .nemotronMultilingual:
            return false
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
        true
    }
}

/// Engine types for model routing
public enum EngineType: Sendable {
    case parakeetUltra
    case parakeetUnified
    case parakeetStreaming
    case nemotronMultilingual
}
