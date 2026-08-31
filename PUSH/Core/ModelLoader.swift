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

    /// Whether changing `changed`'s dictation language has to reload an engine now.
    ///
    /// Only the *active* engine is holding a language in memory. Every other
    /// engine reads `AppState.language(for:)` on its way up, so a preference
    /// recorded for a model the user isn't running needs nothing more than the
    /// write — reloading it would download and warm a model to serve nobody.
    ///
    /// `nonisolated` and parameterised rather than reading `AppState.shared`
    /// itself so the decision can be tested without standing up the singleton;
    /// `reloadForLanguageChange` and the picker both route through this one
    /// predicate so the view's "should I even start a task" question and the
    /// loader's guard can never answer differently.
    nonisolated static func languageChangeNeedsReload(
        changed: AppState.WhisperModel,
        activeModel: AppState.WhisperModel,
        isModelReady: Bool
    ) -> Bool {
        isModelReady && changed == activeModel
    }

    /// Re-load `model` so a language change takes effect on the running engine.
    ///
    /// Exists because `activate(_:)` deliberately early-returns when the model
    /// is already active — the right call for a repeated row tap, and exactly
    /// wrong here. Without this path a user switches to Portuguese, watches the
    /// picker update, and keeps dictating in English until they quit the app.
    ///
    /// Not folded into `activate` as a `force:` flag: the two differ in more
    /// than a guard. There is no previous engine to keep serving and no
    /// engine-family swap to unload, and the failure state is different — a
    /// half-completed language reload leaves *nothing* resident (both engines
    /// tear down before they rebuild), so it has to report the model as
    /// unavailable rather than "the old one is still fine".
    ///
    /// Errors are absorbed rather than thrown: the caller is a picker whose
    /// choice has already been recorded, `AppState` carries the outcome, and
    /// there is no useful "undo the user's language" to perform.
    static func reloadForLanguageChange(_ model: AppState.WhisperModel) async {
        let state = AppState.shared
        guard languageChangeNeedsReload(changed: model,
                                        activeModel: state.activeModel,
                                        isModelReady: state.isModelReady) else { return }

        // Queued behind any in-flight activation on the same chain as
        // `activate`. A language reload racing a model switch would otherwise
        // let the slower of the two commit last and leave the engine serving a
        // language nobody asked for.
        let previousTask = currentActivation
        let task = Task {
            _ = await previousTask?.result
            try await performLanguageReload(model)
        }
        currentActivation = task
        _ = await task.result
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

    /// Reloads the already-active `model`, picking up whatever language
    /// `AppState` now holds for it.
    ///
    /// `load(_:)` is reused rather than reimplemented, and that is the whole
    /// trick: its `.nemotronMultilingual` arm already reads the saved code and
    /// hands it to the engine (which decides for itself whether that is a cheap
    /// prompt swap or a genuine build swap), and its `.appleSpeech` arm already
    /// pushes the code through `setPreferredLanguage(_:)`, which drops
    /// `readyLocale` so the `loadModel()` on the next line actually re-resolves.
    /// A second copy of that routing here would be one more place to forget an
    /// engine.
    ///
    /// `isModelReady` is left true across the load, matching `activate`'s
    /// same-family switch: the flag means "this app has a model", and the
    /// engine's own reentrancy guard is what protects the swap. `isWarmingUp`
    /// and the status message are what tell the user something is happening.
    private static func performLanguageReload(_ model: AppState.WhisperModel) async throws {
        let state = AppState.shared

        // Re-checked after the queue wait: the activation we queued behind may
        // have been a switch to a different model, in which case this reload is
        // now about an engine that is no longer running.
        guard state.activeModel == model else { return }

        state.isWarmingUp = true
        state.statusMessage = "Loading \(model.shortName)…"
        PushLogger.log("ModelLoader: Reloading \(model.rawValue) for a language change...")
        let loadStart = Date()

        do {
            try await load(model)
        } catch {
            // Unlike a failed activation there is no previous model still
            // serving to fall back on — both language-taking engines release
            // what they had before they load the new language — so this reports
            // the honest state rather than a reassuring one.
            state.isWarmingUp = false
            state.isModelReady = false
            state.modelUnavailable = true
            state.statusMessage = "Model failed to load"
            PushLogger.log("ModelLoader: ❌ Failed to reload \(model.rawValue): \(error)")
            NotificationManager.shared.showModelError()
            throw error
        }

        PushLogger.log("ModelLoader: Reloaded in \(String(format: "%.2f", Date().timeIntervalSince(loadStart)))s")
        state.modelUnavailable = false
        state.isModelReady = true

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
