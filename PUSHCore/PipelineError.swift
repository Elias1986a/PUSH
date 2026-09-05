import Foundation

/// Failures that belong to routing itself rather than to any one engine.
public enum PipelineError: LocalizedError {
    /// Reachable only from a saved preference that outlived a downgrade — the picker
    /// filters this model out on systems that can't run it.
    case requiresNewerSystem

    public var errorDescription: String? {
        switch self {
        case .requiresNewerSystem:
            return "Apple Speech requires macOS 26 or later"
        }
    }
}
