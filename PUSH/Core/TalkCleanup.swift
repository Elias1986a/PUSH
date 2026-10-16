import Foundation
import Observation
import PUSHCore

/// The Talk cleanup models on disk, each pass's download, and whether its
/// engine is loaded. Nothing here downloads on its own — only the user
/// pressing Download should spend the bytes.
@MainActor
@Observable
final class TalkCleanupStore {
    static let shared = TalkCleanupStore()

    nonisolated static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PUSH/TalkModels", isDirectory: true)

    private(set) var onDisk: Set<TalkCleanupPass> = []
    private(set) var ready: Set<TalkCleanupPass> = []
    private(set) var downloading: TalkCleanupPass?
    private(set) var progress: Double = 0
    private(set) var lastError: [TalkCleanupPass: String] = [:]

    private var downloadTask: Task<Void, Never>?

    private init() { refresh() }

    /// One fixed name per pass: the downloader only moves a file in once its
    /// size and SHA-256 check out, so being there means being whole.
    nonisolated static func url(for pass: TalkCleanupPass) -> URL {
        directory.appendingPathComponent("\(pass.rawValue).gguf")
    }

    func refresh() {
        onDisk = Set(TalkCleanupPass.allCases.filter {
            FileManager.default.fileExists(atPath: Self.url(for: $0).path)
        })
    }

    func download(_ pass: TalkCleanupPass) {
        guard downloading == nil else { return }
        downloading = pass
        progress = 0
        lastError[pass] = nil
        PushLogger.log("TalkCleanupStore: downloading \(pass.rawValue)")
        downloadTask = Task {
            do {
                let file = try await HuggingFaceFile.resolve(repo: pass.repo, suffix: pass.fileSuffix)
                let spec = ModelFileDownloader.Spec(url: file.downloadURL, bytes: file.bytes, sha256: file.sha256)
                try await ModelFileDownloader().download(spec, to: Self.url(for: pass)) { value in
                    Task { @MainActor in TalkCleanupStore.shared.progress = value }
                }
                PushLogger.log("TalkCleanupStore: \(pass.rawValue) downloaded and verified (\(file.path) @ \(file.revision.prefix(7)))")
            } catch is CancellationError {
                PushLogger.log("TalkCleanupStore: download of \(pass.rawValue) cancelled")
            } catch let error as URLError where error.code == .cancelled {
                PushLogger.log("TalkCleanupStore: download of \(pass.rawValue) cancelled")
            } catch {
                lastError[pass] = error.localizedDescription
                PushLogger.log("TalkCleanupStore: download of \(pass.rawValue) failed: \(error)")
            }
            downloading = nil
            downloadTask = nil
            refresh()
            TalkCleanupLoader.apply()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func delete(_ pass: TalkCleanupPass) async {
        await TalkCleanupLoader.unload(pass)
        for suffix in ["", ".partial"] {
            try? FileManager.default.removeItem(atPath: Self.url(for: pass).path + suffix)
        }
        PushLogger.log("TalkCleanupStore: deleted \(pass.rawValue)")
        refresh()
    }

    fileprivate func setReady(_ pass: TalkCleanupPass, _ isReady: Bool) {
        if isReady { ready.insert(pass) } else { ready.remove(pass) }
    }
}

/// Keeps each pass's engine loaded while its switch is on and its model is on
/// disk, unloaded otherwise. Only this type loads or unloads them.
@MainActor
enum TalkCleanupLoader {
    private static var generation: [TalkCleanupPass: Int] = [:]
    private static var loaded: Set<TalkCleanupPass> = []

    static func apply() {
        for pass in TalkCleanupPass.allCases {
            let wanted = AppState.shared.isTalkCleanupOn(pass) && TalkCleanupStore.shared.onDisk.contains(pass)
            if wanted == loaded.contains(pass) { continue }
            load(pass, wanted)
        }
    }

    static func unload(_ pass: TalkCleanupPass) async {
        generation[pass, default: 0] &+= 1
        loaded.remove(pass)
        TalkCleanupStore.shared.setReady(pass, false)
        await TalkCleanupRunner.engine(pass).unload()
    }

    private static func load(_ pass: TalkCleanupPass, _ wanted: Bool) {
        generation[pass, default: 0] &+= 1
        let current = generation[pass]
        // Marked now, so a second apply() before this finishes starts nothing.
        if wanted { loaded.insert(pass) } else { loaded.remove(pass) }
        TalkCleanupStore.shared.setReady(pass, false)
        let engine = TalkCleanupRunner.engine(pass)
        Task {
            guard wanted else {
                await engine.unload()
                PushLogger.log("TalkCleanupLoader: \(pass.rawValue) unloaded")
                return
            }
            let start = Date()
            do {
                // The prompt is a few hundred tokens of instructions and examples.
                try await engine.load(path: TalkCleanupStore.url(for: pass).path, contextSize: 2048)
                // Compile the GPU code now, not on the first dictation.
                for try await _ in await engine.complete(prompt: pass.prompt(for: "hello there everyone"),
                                                         maxTokens: 1, parseSpecial: true) {}
            } catch {
                PushLogger.log("TalkCleanupLoader: loading \(pass.rawValue) failed: \(error)")
                await engine.unload()
                if current == generation[pass] { loaded.remove(pass) }
                return
            }
            guard current == generation[pass] else { return }
            TalkCleanupStore.shared.setReady(pass, true)
            PushLogger.log("TalkCleanupLoader: \(pass.rawValue) ready in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        }
    }
}

/// Runs the switched-on passes over a finished English transcript.
enum TalkCleanupRunner {
    private static let engines: [TalkCleanupPass: LlamaEngine] =
        Dictionary(uniqueKeysWithValues: TalkCleanupPass.allCases.map { ($0, LlamaEngine()) })

    static func engine(_ pass: TalkCleanupPass) -> LlamaEngine { engines[pass]! }

    /// Copying the input back is the job, so nothing may push the model off
    /// the words already in the prompt: no repetition penalty.
    private static let copying: LlamaEngine.Sampling = {
        var sampling = LlamaEngine.Sampling()
        sampling.repetitionPenalty = 1
        sampling.penaltyLastN = 0
        return sampling
    }()

    /// Punctuation first, then autocorrect, each line on its own (the engine
    /// stops at a newline, and spoken formatting can make lists). Logs only
    /// counts and timings — never the text.
    static func run(_ text: String) async -> String {
        let ready = await MainActor.run { TalkCleanupStore.shared.ready }
        var out = text
        for pass in TalkCleanupPass.allCases where ready.contains(pass) {
            let start = DispatchTime.now()
            var kept = 0, rejected = 0
            var lines = out.components(separatedBy: "\n")
            for index in lines.indices {
                guard let line = TalkCleanupPass.sendable(lines[index]) else { continue }
                if let answer = await generate(pass, line.body), let accepted = pass.accept(answer, for: line.body) {
                    lines[index] = line.marker + accepted
                    kept += 1
                } else {
                    rejected += 1
                }
            }
            out = lines.joined(separator: "\n")
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
            PushLogger.log("TalkCleanup: \(pass.rawValue) \(kept) kept, \(rejected) rejected, \(Int(ms))ms")
            ReleaseTiming.mark(pass.rawValue)
        }
        return out
    }

    /// The model's answer, or nil on an error or past the pass's timeout.
    private static func generate(_ pass: TalkCleanupPass, _ line: String) async -> String? {
        let engine = engine(pass)
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var answer = ""
                do {
                    for try await piece in await engine.complete(prompt: pass.prompt(for: line),
                                                                 maxTokens: pass.maxTokens(for: line),
                                                                 sampling: copying, parseSpecial: true) {
                        answer += piece
                    }
                } catch {
                    return nil
                }
                return Task.isCancelled ? nil : answer
            }
            group.addTask {
                try? await Task.sleep(for: pass.timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
