import FluidAudio
import Foundation

/// The exact Hugging Face commit each speech model is downloaded from.
///
/// FluidAudio fetches from a repository's `main` branch unless told otherwise,
/// so whatever was pushed there last is what a new user would get, unseen and
/// untested by us — the TYPE models were already pinned and checksummed
/// (`TypingModel`), the speech models were not. Pinned, every download is the
/// files we tested, and a change upstream reaches users only when one of these
/// is updated here on purpose (re-test, then bump).
///
/// Recorded 2026-10-14 from each repository's `main`, unchanged since
/// June–September 2026, i.e. the models every build so far has been tested on.
public enum SpeechModelPins {
    public static let revisions: [String: String] = [
        // Parakeet Ultra
        "FluidInference/parakeet-ultra-coreml": "95eaa59a39d4394f047a4dc5cce480388a60d1b6",
        // Parakeet Streaming (the unified English model's streaming encoder)
        "FluidInference/parakeet-unified-en-0.6b-coreml": "d32e972dd4315f1dc3f6be28fb2aab0ab3e80358",
        // Nemotron Multilingual
        "FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML": "1a41b75758b0337ff67db7d5408280aaaf23074e",
        // Silero voice activity detection
        "FluidInference/silero-vad-coreml": "b419383c55c110e2c9271fa6ee0ea83d03c70d96",
    ]

    /// Before anything downloads: at launch, ahead of the first model load.
    public static func apply(modelsDirectory: URL = defaultModelsDirectory) {
        adoptExistingDownloads(in: modelsDirectory)
        var overrides = ModelRegistry.revisionOverrides
        for (repo, revision) in revisions { overrides[repo] = revision }
        ModelRegistry.revisionOverrides = overrides
    }

    /// FluidAudio's speech model cache.
    public static var defaultModelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// The marker FluidAudio writes beside a pinned download.
    static let revisionMarker = ".fluidaudio-revision"

    /// Marks models already downloaded from `main` as the pinned commit.
    ///
    /// FluidAudio counts an unmarked folder as `main` and, once a revision
    /// is pinned, deletes it and downloads the model again: 600 MB each for
    /// Ultra and Streaming at the first launch after an update, the very
    /// download launch must never start (seen 2026-10-14). These files came
    /// from `main` while it held these commits, so they are the pinned ones.
    /// Nemotron reuses its folders without a revision check and needs nothing.
    static func adoptExistingDownloads(in modelsDirectory: URL) {
        let fm = FileManager.default
        for (remotePath, revision) in revisions {
            guard let repo = Repo(rawValue: remotePath), repo != .nemotronMultilingual else { continue }
            let folder = modelsDirectory.appendingPathComponent(repo.folderName, isDirectory: true)
            let marker = folder.appendingPathComponent(revisionMarker)
            guard !fm.fileExists(atPath: marker.path),
                  let contents = try? fm.contentsOfDirectory(atPath: folder.path),
                  !contents.isEmpty
            else { continue }
            try? Data((revision + "\n").utf8).write(to: marker, options: .atomic)
            PushLogger.log("SpeechModelPins: kept the downloaded \(repo.folderName) as the pinned version")
        }
    }
}
