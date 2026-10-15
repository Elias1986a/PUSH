import FluidAudio

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
    public static func apply() {
        var overrides = ModelRegistry.revisionOverrides
        for (repo, revision) in revisions { overrides[repo] = revision }
        ModelRegistry.revisionOverrides = overrides
    }
}
