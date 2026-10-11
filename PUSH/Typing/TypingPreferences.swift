import Foundation
import PUSHCore

/// Type's saved choices. Per-machine like the speech model: a model is a
/// download, and which ones are on disk differs between Macs.
enum TypingPreferences {
    static let modelKey = "typing.model"
    static let lengthKey = "typing.length"

    static func model(in d: UserDefaults = .standard) -> TypingModel {
        d.string(forKey: modelKey).flatMap(TypingModel.init(rawValue:)) ?? .defaultModel
    }

    /// Never longer than the saved model handles well.
    static func length(in d: UserDefaults = .standard) -> LengthPreset {
        let saved = d.string(forKey: lengthKey).flatMap(LengthPreset.init(rawValue:)) ?? .defaultPreset
        return saved.clamped(to: model(in: d))
    }
}
