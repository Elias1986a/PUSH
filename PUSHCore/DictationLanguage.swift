import Foundation

/// A language a user can choose to dictate in.
///
/// Deliberately a thin wrapper over a code rather than an enum of languages:
/// the set of supported languages is a property of each *model*, discovered at
/// runtime (Nemotron reads its own `metadata.json`; Apple queries
/// `SpeechTranscriber.supportedLocales`). An enum here would be a second list
/// to maintain and a guaranteed source of drift.
public struct DictationLanguage: Sendable, Hashable, Identifiable, Comparable {
    /// BCP-47 code, canonicalized by `init`. Hyphenated, so "en-US" — never the
    /// underscore form, whatever the engine handed us.
    public let code: String

    /// Canonicalizes on the way in, because the two engines spell the same
    /// language differently: Apple Speech reports `Locale.identifier`, which is
    /// underscored ("en_US"), while Nemotron reports hyphenated BCP-47 from its
    /// `metadata.json` prompt dictionary ("en-US"). Both lists reach the same
    /// picker. Left raw, the user would see "English (United States)" twice and
    /// the two values would compare unequal — breaking the Picker tag, which is
    /// identity-based, and the UserDefaults round-trip that restores a saved
    /// choice.
    ///
    /// The same pass folds case ("EN" → "en") and maps ISO 639-2/3 onto 639-1
    /// ("eng" → "en"); the latter is what makes `isEnglish` correct for "eng".
    /// Unrecognised input degrades rather than throwing: "" becomes "und"
    /// (named "Unknown language" downstream), and "xx" / "zzzz" pass through
    /// untouched to be shown as themselves.
    public init(code: String) {
        self.code = Locale(identifier: code).identifier(.bcp47)
    }

    public var id: String { code }

    /// Human-readable name as `locale` would write it.
    ///
    /// The locale is injected rather than always `.current` so the naming can
    /// be tested against a fixed locale instead of whatever machine runs the
    /// suite.
    public func displayName(in locale: Locale) -> String {
        if let full = locale.localizedString(forIdentifier: code) { return full }

        // Fall back to the language subtag ICU actually parsed — never to the
        // first two characters of the code. `String(code.prefix(2))` named
        // "fil" Finnish, "haw" Hausa, "ceb" Chechen and "tlh" Tagalog: a
        // *different* language's name, stated with total confidence, which is
        // worse for the user than showing the raw code.
        if let subtag = Locale(identifier: code).language.languageCode?.identifier,
           let name = locale.localizedString(forLanguageCode: subtag) {
            return name
        }

        // Nothing the OS can name. The raw code at least tells the truth.
        return code
    }

    /// Human-readable name in the user's own locale, from the OS.
    public var displayName: String { displayName(in: .current) }

    /// English gets post-processing (number words, "i" → "I", the entity gate)
    /// that is meaningless or harmful in other languages.
    ///
    /// Matched on the parsed language subtag rather than `hasPrefix("en")`,
    /// which was also true of Enga ("enq"), "enb" and Middle English ("enm")
    /// and would have run the English rules over their transcripts.
    public var isEnglish: Bool {
        Locale(identifier: code).language.languageCode?.identifier == "en"
    }

    /// Ordered by display name, not by code: the picker is read by a human, and
    /// "de-DE" sorting before "es-ES" would put German before Spanish only by
    /// accident of the codes agreeing with the names.
    ///
    /// Ties fall back to the code so the ordering stays trichotomous against
    /// the code-based `==`. Two distinct codes really can share a name —
    /// "fil-XX" and "fil-YY" are both "Filipino" — and without the tie-break
    /// they would be neither equal nor ordered, which breaks the strict weak
    /// ordering `sorted()` assumes.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        switch lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.code < rhs.code
        }
    }
}
