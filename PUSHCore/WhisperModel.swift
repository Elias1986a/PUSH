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
/// Parakeet Unified went in 8.2.5 the same way: once PUSH decoded while you talk, it
/// was neither faster nor more accurate than Ultra (13 benchmark readings), and English
/// only; a saved "parakeet-unified" falls back to the default.
public enum WhisperModel: String, CaseIterable, Identifiable, Sendable {
    case parakeetUltra = "parakeet-ultra"
    case parakeetStreaming = "parakeet-streaming"
    case nemotronMultilingual = "nemotron-multilingual"

    public var id: String { rawValue }

    /// The model a fresh install uses, and what launch falls back to first.
    ///
    /// By the Mac's language since 8.2.5. On an English Mac, Parakeet Streaming:
    /// your words appear in the pill as you speak, which is what the website
    /// shows, and it is the fastest after release (0.02 s against Ultra's
    /// 0.04 s — both far below what anyone notices). Anywhere else, Parakeet
    /// Ultra, which follows English and the Latin-script European languages on
    /// its own; Streaming is English only.
    public static var defaultModel: WhisperModel { defaultModel(for: Locale.preferredLanguages) }

    public static func defaultModel(for preferredLanguages: [String]) -> WhisperModel {
        (preferredLanguages.first ?? "en").lowercased().hasPrefix("en") ? .parakeetStreaming : .parakeetUltra
    }

    /// The cases the picker should offer, ordered for the settings list rather
    /// than by declaration: the recommended default leads and the multilingual
    /// engine comes last. `allCases` order is the enum's own business and the
    /// comparison tool still relies on it.
    public static var selectable: [WhisperModel] {
        let parakeet: [WhisperModel] = defaultModel == .parakeetUltra
            ? [.parakeetUltra, .parakeetStreaming] : [.parakeetStreaming, .parakeetUltra]
        return parakeet + [.nemotronMultilingual]
    }

    public var displayName: String {
        switch self {
        case .parakeetUltra: return "Parakeet Ultra — English and European languages"
        case .parakeetStreaming: return "Parakeet Streaming — Visualize as you talk"
        case .nemotronMultilingual: return "Nemotron Multilingual — Other languages"
        }
    }

    /// The model's name on its own.
    ///
    /// `displayName` carries a trailing qualifier because it had to sell the
    /// model from inside a one-line popup button. The settings list shows
    /// description and size in their own rows, so the name can just be the
    /// name — and this is also what belongs in a status message.
    public var shortName: String {
        switch self {
        case .parakeetUltra: return "Parakeet Ultra"
        case .parakeetStreaming: return "Parakeet Streaming"
        case .nemotronMultilingual: return "Nemotron Multilingual"
        }
    }

    /// Short qualifier shown beside the name, where one earns its place.
    /// "Recommended" follows the default, which depends on the Mac's language.
    public var badge: String? {
        if self == Self.defaultModel { return "Recommended" }
        return self == .nemotronMultilingual ? "Multilingual" : nil
    }

    /// Approximate on-disk cost, for the settings list. Matches the figures
    /// `modelDescription` quotes and the progress estimates in the download.
    public var downloadSizeLabel: String {
        "600 MB"
    }

    public var modelDescription: String {
        switch self {
        case .parakeetUltra:
            return "Accurate, and understands English and the European languages written in the Latin alphabet — Spanish, French, German, Italian, Portuguese and more — and switches between them on its own. For other languages, use Nemotron Multilingual."
        case .parakeetStreaming:
            return "English only. Shows your words as you speak and transcribes while you talk, so text lands the moment you let go."
        case .nemotronMultilingual:
            return "For languages Parakeet Ultra doesn't cover — Chinese, Japanese, Arabic, Hindi, Russian, Greek and more. Streams as you speak, in the language you pick. For English and European languages like Spanish, French and German, use Parakeet Ultra."
        }
    }

    /// The engine type used by this model
    public var engineType: EngineType {
        switch self {
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
        case .parakeetUltra, .parakeetStreaming: return false
        }
    }

    /// Whether this engine picks the language itself on each dictation, so the
    /// transcript's language has to be read from the text afterwards
    /// (`TranscriptLanguage.detect`) rather than from a setting.
    public var detectsLanguagePerUtterance: Bool {
        switch self {
        case .parakeetUltra: return true
        case .parakeetStreaming, .nemotronMultilingual:
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
    case parakeetStreaming
    case nemotronMultilingual
}
