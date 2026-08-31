import Foundation
import PUSHCore

/// Central model lifecycle. Loads a model, swaps it in as `AppState.activeModel`,
/// unloads the previous engine, and warms up — keeping dictation available on the
/// old model until the new one is actually ready, so switching never interrupts use.
@MainActor
enum ModelLoader {

    /// Serializes activations so rapid picker changes can't interleave state.
    private static var currentActivation: Task<Void, Error>?

    /// Load `model` and make it the active model. If a model is already active it
    /// keeps serving until the swap; on failure the previous model stays active.
    /// Throws so callers (Settings) can surface the error; launch can ignore it —
    /// state and a user notification are handled here either way.
    static func activate(_ model: AppState.WhisperModel) async throws {
        let previousTask = currentActivation
        let task = Task {
            _ = await previousTask?.result
            try await performActivation(model)
        }
        currentActivation = task
        try await task.value
    }

    /// Unload the active model and mark the app as having no model (used when
    /// the user deletes the active model's files).
    static func deactivate() async {
        let state = AppState.shared
        await unload(state.activeModel)
        state.isModelReady = false
        state.modelUnavailable = true
        state.statusMessage = "Model unavailable"
        PushLogger.log("ModelLoader: Deactivated \(state.activeModel.rawValue)")
    }

    /// Point the streaming engine's partials back at the live dictation preview.
    ///
    /// The engine no longer knows about AppState; it just reports partials. The
    /// decision about whether a partial should be shown is the app's, and it is
    /// asked here rather than inside the engine.
    ///
    /// Named rather than inlined into `load` because `setOnPartial` is a single
    /// slot: the teleprompter borrows it for the length of a take and has to be
    /// able to give it back. Restoring by re-activating the model wouldn't do —
    /// `performActivation` early-returns when the model is already active, which
    /// is exactly the case when the user was on streaming to begin with.
    static func installDictationPartialHandler() async {
        await ParakeetStreamingEngine.shared.setOnPartial { partial in
            Task { @MainActor in
                guard AppState.shared.showLivePreview,
                      AppState.shared.isListening else { return }
                AppState.shared.livePartialText = partial
            }
        }
    }

    // MARK: - Private

    private static func performActivation(_ model: AppState.WhisperModel) async throws {
        let state = AppState.shared
        if state.isModelReady, state.activeModel == model {
            return
        }

        let previous = state.activeModel
        let hadModel = state.isModelReady
        state.isWarmingUp = true
        state.statusMessage = hadModel ? "Loading \(model.shortName)…" : "Loading AI model…"
        PushLogger.log("ModelLoader: Activating \(model.rawValue)...")
        let loadStart = Date()

        do {
            try await load(model)
        } catch {
            state.isWarmingUp = false
            if hadModel {
                // The previous model is still loaded and serving.
                state.statusMessage = "Ready"
            } else {
                state.modelUnavailable = true
                state.statusMessage = "Model failed to load"
            }
            PushLogger.log("ModelLoader: ❌ Failed to load \(model.rawValue): \(error)")
            NotificationManager.shared.showModelError()
            throw error
        }

        PushLogger.log("ModelLoader: Model loaded in \(String(format: "%.2f", Date().timeIntervalSince(loadStart)))s")
        state.activeModel = model
        state.modelUnavailable = false
        state.isModelReady = true

        // Free the previous engine's memory when switching engine families.
        // (Same-family switches replace the model inside the engine already.)
        if hadModel, previous.engineType != model.engineType {
            await unload(previous)
        }

        // Warm shaders in the background — the app is already usable; the
        // indicator just explains why the first transcription may be slower.
        state.statusMessage = "Warming up AI model…"
        await warmup(model)
        state.isWarmingUp = false
        if state.statusMessage == "Warming up AI model…" {
            state.statusMessage = "Ready"
        }
    }

    private static func load(_ model: AppState.WhisperModel) async throws {
        switch model.engineType {
        case .parakeet: try await ParakeetEngine.shared.loadModel()
        case .parakeetUnified: try await ParakeetUnifiedEngine.shared.loadModel()
        case .parakeetStreaming:
            await installDictationPartialHandler()
            try await ParakeetStreamingEngine.shared.loadModel()
        case .nemotronMultilingual:
            // The engine has no zero-arg `loadModel()` by design — which build it
            // downloads and which prompt embedding it pins both follow from the
            // language, so there is no sensible "load it, we'll say later".
            //
            // One property read inside the hop, nothing more: this runs on the
            // model-loading path, and a `MainActor.run` that did I/O here would
            // stall the main thread long enough for macOS to disable the event
            // tap and silently drop hotkey presses.
            let code = await MainActor.run { AppState.shared.language(for: .nemotronMultilingual).code }
            try await NemotronMultilingualEngine.shared.loadModel(languageCode: code)
        case .appleSpeech:
            guard #available(macOS 26, *) else { throw PipelineError.requiresNewerSystem }
            // Push the saved preference in before loading. `AppleSpeechEngine`
            // deliberately does not persist it — it is handed a code and forgets
            // it on quit, falling back to its old system-locale guess. Without
            // this line the picker appears to do nothing after a relaunch.
            let code = await MainActor.run { AppState.shared.language(for: .appleSpeech).code }
            await AppleSpeechEngine.shared.setPreferredLanguage(code)
            try await AppleSpeechEngine.shared.loadModel()
        }
    }

    private static func unload(_ model: AppState.WhisperModel) async {
        switch model.engineType {
        case .parakeet: await ParakeetEngine.shared.unloadModel()
        case .parakeetUnified: await ParakeetUnifiedEngine.shared.unloadModel()
        case .parakeetStreaming: await ParakeetStreamingEngine.shared.unloadModel()
        // No language: tearing the model down is the same act whichever one was loaded.
        case .nemotronMultilingual: await NemotronMultilingualEngine.shared.unloadModel()
        case .appleSpeech:
            if #available(macOS 26, *) { await AppleSpeechEngine.shared.unloadModel() }
        }
    }

    private static func warmup(_ model: AppState.WhisperModel) async {
        switch model.engineType {
        case .parakeet: await ParakeetEngine.shared.warmup()
        case .parakeetUnified: await ParakeetUnifiedEngine.shared.warmup()
        case .parakeetStreaming: await ParakeetStreamingEngine.shared.warmup()
        case .nemotronMultilingual:
            let code = await MainActor.run { AppState.shared.language(for: .nemotronMultilingual).code }
            await NemotronMultilingualEngine.shared.warmup(languageCode: code)
        case .appleSpeech:
            if #available(macOS 26, *) { await AppleSpeechEngine.shared.warmup() }
        }
    }
}
