import Foundation
import PUSHCore

/// Type's saved choices. Per-machine like the speech model: a model is a
/// download, and which ones are on disk differs between Macs.
enum TypingPreferences {
    static let modelKey = "typing.model"
    static let lengthKey = "typing.length"
    static let codeEditorsKey = "typing.codeEditors"
    static let colorKey = "typing.color"
    static let spaceAfterKey = "typing.spaceAfterLastWord"
    static let pauseOnBatteryKey = "typing.pauseOnBattery"
    static let excludedAppsKey = "typing.excludedApps"
    static let pausedUntilKey = "typing.pausedUntil"
    static let showIndicatorKey = "typing.showIndicator"
    static let nameKey = "typing.profile.name"
    static let aboutKey = "typing.profile.about"
    /// The About note's limit (Cotabby keeps its style line to 300).
    static let aboutLimit = 300

    static func model(in d: UserDefaults = .standard) -> TypingModel {
        d.string(forKey: modelKey).flatMap(TypingModel.init(rawValue:)) ?? .defaultModel
    }

    /// Never longer than the saved model handles well.
    static func length(in d: UserDefaults = .standard) -> LengthPreset {
        let saved = d.string(forKey: lengthKey).flatMap(LengthPreset.init(rawValue:)) ?? .defaultPreset
        return saved.clamped(to: model(in: d))
    }

    /// Off by default: editors have their own completions (and AI ones) on
    /// Tab, and a blue suggestion would take Tab away from them.
    static func codeEditors(in d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: codeEditorsKey)
    }

    static func color(in d: UserDefaults = .standard) -> SuggestionColor {
        SuggestionColor(saved: d.string(forKey: colorKey))
    }

    /// On by default (Cotypist and Cotabby both offer it; the user asked for
    /// it): finishing a suggestion types the space before the next word.
    static func spaceAfterLastWord(in d: UserDefaults = .standard) -> Bool {
        d.object(forKey: spaceAfterKey) as? Bool ?? true
    }

    /// Off by default: a laptop on battery still has plenty for a 1–3 GB model.
    static func pauseOnBattery(in d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: pauseOnBatteryKey)
    }

    /// Apps the user turned Type off in, by bundle id (the built-in list —
    /// password managers and the like — is `TypingExclusions`).
    static func excludedApps(in d: UserDefaults = .standard) -> [String] {
        d.stringArray(forKey: excludedAppsKey) ?? []
    }

    /// "Pause for 1 hour / until tomorrow"; a date already past means not paused.
    static func pausedUntil(in d: UserDefaults = .standard) -> Date? {
        (d.object(forKey: pausedUntilKey) as? Date).flatMap { $0 > Date() ? $0 : nil }
    }

    static func name(in d: UserDefaults = .standard) -> String { d.string(forKey: nameKey) ?? "" }
    static func about(in d: UserDefaults = .standard) -> String { d.string(forKey: aboutKey) ?? "" }

    /// The name used at a sign-off: the user's own choice, else the first
    /// word of the account's full name.
    static func signOffName(saved: String, fullName: String = NSFullUserName()) -> String? {
        let chosen = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chosen.isEmpty { return chosen }
        return fullName.split(separator: " ").first.map(String.init)
    }

    /// On by default: the field icon is how the user knows Type is working there.
    static func showIndicator(in d: UserDefaults = .standard) -> Bool {
        d.object(forKey: showIndicatorKey) as? Bool ?? true
    }
}
