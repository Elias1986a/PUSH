import Foundation

/// Which of PUSH's features this Mac runs. Per-machine on purpose: each
/// feature needs a model on disk, and models are never synced.
enum FeatureSwitches {
    static let dictationKey = "feature.dictationEnabled"
    static let typeKey = "feature.typeEnabled"

    /// Absent means on, so every install from before this switch existed
    /// keeps dictating exactly as it did.
    static func dictationEnabled(in d: UserDefaults = .standard) -> Bool {
        d.object(forKey: dictationKey) as? Bool ?? true
    }

    static func typeEnabled(in d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: typeKey)
    }
}
