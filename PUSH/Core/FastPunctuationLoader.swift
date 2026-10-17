import Foundation
import PUSHCore

/// The fast punctuation model: loaded whenever its files are on disk, and
/// run on every English dictation, with no switch. The files come down with
/// the English speech models (`ModelDownload`), or from "Get punctuation" in
/// Settings ▸ Models, and go when the last English model is deleted.
@MainActor
enum FastPunctuationLoader {
    /// Under TalkModels, where the Talk cleanup models lived while on trial;
    /// moving it would orphan the files already downloaded.
    nonisolated static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PUSH/TalkModels/punctuation-fast", isDirectory: true)
    private static var generation = 0
    private(set) static var model: FastPunctuation?

    /// Every pinned file, at its full size (the downloader only moves a file
    /// in once its SHA-256 checks out).
    nonisolated static var isOnDisk: Bool {
        FastPunctuation.files.allSatisfy { file in
            let size = (try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(file.path).path)[.size]) as? Int64
            return size == file.bytes
        }
    }

    /// When the last English speech model is deleted: punctuation only ever
    /// runs on their text.
    static func deleteFiles() {
        generation &+= 1
        model = nil
        try? FileManager.default.removeItem(at: directory)
        PushLogger.log("FastPunctuationLoader: files deleted")
    }

    private static var downloadTask: Task<Void, Error>?

    /// Fetches the pinned files (about 58 MB), resumable and SHA-256 checked,
    /// reporting bytes on disk. Joins a download already running.
    static func download(onBytes: @escaping @MainActor (Int64) -> Void = { _ in }) async throws {
        if isOnDisk { onBytes(FastPunctuation.totalBytes); return }
        if let downloadTask { return try await downloadTask.value }
        let task = Task {
            var done: Int64 = 0
            for file in FastPunctuation.files {
                let base = done
                let spec = ModelFileDownloader.Spec(url: file.url, bytes: file.bytes, sha256: file.sha256)
                try await ModelFileDownloader().download(spec, to: directory.appendingPathComponent(file.path)) { fraction in
                    Task { @MainActor in onBytes(base + Int64(Double(file.bytes) * fraction)) }
                }
                done += file.bytes
            }
            PushLogger.log("FastPunctuationLoader: downloaded and verified (\(FastPunctuation.revision.prefix(7)))")
        }
        downloadTask = task
        defer { downloadTask = nil }
        try await task.value
        apply()
    }

    static func apply() {
        generation &+= 1
        let current = generation
        guard isOnDisk else {
            if model != nil { PushLogger.log("FastPunctuationLoader: unloaded") }
            model = nil
            return
        }
        guard model == nil else { return }
        Task {
            let start = Date()
            do {
                // Off the main thread: CoreML's first load takes seconds, and a
                // blocked main thread froze Settings and can drop the hotkey tap.
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try FastPunctuation(directory: directory)
                }.value
                try await loaded.warmUp()
                guard current == generation else { return }
                model = loaded
                PushLogger.log("FastPunctuationLoader: ready in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
            } catch {
                PushLogger.log("FastPunctuationLoader: loading failed: \(error)")
            }
        }
    }

    /// The text re-punctuated, or as it was when the model isn't loaded or
    /// fails. Logs the time only — never the text.
    nonisolated static func run(_ text: String) async -> String {
        guard let model = await MainActor.run(body: { FastPunctuationLoader.model }) else { return text }
        let start = DispatchTime.now()
        do {
            let out = try await model.punctuate(text)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
            PushLogger.log("FastPunctuation: \(Int(ms))ms")
            ReleaseTiming.mark("fast punctuation")
            return out
        } catch {
            PushLogger.log("FastPunctuation: failed (\(error)); kept the speech model's punctuation")
            return text
        }
    }
}
