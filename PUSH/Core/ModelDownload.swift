import Foundation
import PUSHCore

/// Download (when needed), load and warm a model, with coarse progress.
///
/// Shared by Settings ▸ Models and the onboarding model step, so the two can
/// never disagree about how a download is started or measured. The engines
/// report no progress of their own, so it is read off the size of the model's
/// folder once a second against the expected ~600 MB, and capped at 95% until
/// the load itself returns.
@MainActor
enum ModelDownload {
    static let expectedBytes: Double = 600_000_000

    /// Throws what `ModelLoader.activate` throws, including `CancellationError`
    /// when a newer activation supersedes this one.
    static func run(_ model: WhisperModel, onProgress: @escaping @MainActor (Double) -> Void) async throws {
        onProgress(0)
        let poll: Task<Void, Never>? = ModelAvailability.folder(for: model).map { folder in
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    // Walking the folder is file I/O: off the main thread, which is
                    // how this app keeps its event tap alive.
                    let onDisk = await Task.detached(priority: .utility) {
                        ModelAvailability.directorySize(at: folder)
                    }.value
                    guard !Task.isCancelled else { return }
                    onProgress(min(onDisk / expectedBytes, 0.95))
                }
            }
        }
        defer { poll?.cancel() }
        try await ModelLoader.activate(model)
        onProgress(1)
    }
}
