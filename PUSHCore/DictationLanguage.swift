import Foundation

/// A language a user can choose to dictate in.
///
/// Deliberately a thin wrapper over a code rather than an enum of languages:
/// the set of supported languages is a property of each *model*, discovered at
/// runtime (Nemotron reads its own `metadata.json`; Apple queries
/// `SpeechTranscriber.supportedLocales`). An enum here would be a second list
/// to maintain and a guaranteed source of drift.
public struct DictationLanguage: Sendable, Hashable, Identifiable, Comparable {
    /// BCP-47 code as the model reports it, e.g. "en-US", "pt-BR", "es".
    public let code: String

    public init(code: String) { self.code = code }

    public var id: String { code }

    /// Human-readable name in the user's own locale, from the OS.
    ///
    /// Falls back to the bare language subtag because models report codes at
    /// mixed granularity — a region-qualified code the OS doesn't recognise
    /// should still name its language rather than surfacing the raw code.
    public var displayName: String {
        Locale.current.localizedString(forIdentifier: code)
            ?? Locale.current.localizedString(forLanguageCode: String(code.prefix(2)))
            ?? code
    }

    /// English gets post-processing (number words, "i" → "I", the entity gate)
    /// that is meaningless or harmful in other languages.
    public var isEnglish: Bool { code.lowercased().hasPrefix("en") }

    /// Ordered by display name, not by code: the picker is read by a human, and
    /// "de-DE" sorting before "es-ES" would put German before Spanish only by
    /// accident of the codes agreeing with the names.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}
