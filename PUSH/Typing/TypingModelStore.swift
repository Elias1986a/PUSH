import Foundation
import Observation
import PUSHCore

/// Type's models on disk: which are there, downloading one with byte progress
/// (resumable, SHA-256 checked) and deleting one. Nothing here downloads on
/// its own — only the user pressing Download should spend gigabytes.
@MainActor
@Observable
final class TypingModelStore {
    static let shared = TypingModelStore()

    nonisolated static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PUSH/TypingModels", isDirectory: true)

    private(set) var onDisk: Set<TypingModel> = []
    private(set) var downloading: TypingModel?
    private(set) var progress: Double = 0
    private(set) var lastError: String?

    private var downloadTask: Task<Void, Never>?

    private init() { refresh() }

    nonisolated static func url(for model: TypingModel) -> URL {
        directory.appendingPathComponent(model.file)
    }

    /// A model counts as on disk only at its full size; a `.partial` does not.
    func refresh() {
        onDisk = Set(TypingModel.allCases.filter { model in
            let size = (try? FileManager.default.attributesOfItem(atPath: Self.url(for: model).path)[.size]) as? Int64
            return size == model.bytes
        })
    }

    func download(_ model: TypingModel) {
        guard downloading == nil else { return }
        downloading = model
        progress = 0
        lastError = nil
        PushLogger.log("TypingModelStore: downloading \(model.rawValue)")
        downloadTask = Task {
            let spec = ModelFileDownloader.Spec(url: model.downloadURL, bytes: model.bytes, sha256: model.sha256)
            do {
                try await ModelFileDownloader().download(spec, to: Self.url(for: model)) { value in
                    Task { @MainActor in TypingModelStore.shared.progress = value }
                }
                PushLogger.log("TypingModelStore: \(model.rawValue) downloaded and verified")
            } catch is CancellationError {
                PushLogger.log("TypingModelStore: download of \(model.rawValue) cancelled; partial kept for resume")
            } catch let error as URLError where error.code == .cancelled {
                PushLogger.log("TypingModelStore: download of \(model.rawValue) cancelled; partial kept for resume")
            } catch {
                lastError = error.localizedDescription
                PushLogger.log("TypingModelStore: download of \(model.rawValue) failed: \(error)")
            }
            downloading = nil
            downloadTask = nil
            refresh()
            TypingEngineLoader.apply()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Unloads it first when it is the model in use.
    func delete(_ model: TypingModel) async {
        await TypingEngineLoader.unloadIfLoaded(model)
        for suffix in ["", ".partial"] {
            try? FileManager.default.removeItem(atPath: Self.url(for: model).path + suffix)
        }
        PushLogger.log("TypingModelStore: deleted \(model.rawValue)")
        refresh()
    }
}
