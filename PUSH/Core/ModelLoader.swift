import Foundation
import PUSHCore

/// Central model lifecycle. Loads a model, swaps it in as `AppState.activeModel`,
/// unloads the previous engine, and warms up — keeping dictation available on the
/// old model until the new one is actually ready, so switching never interrupts use.
@MainActor
enum ModelLoader {

    /// The activation in flight, kept only so a newer one can cancel it.
    private static var currentActivation: Task<Void, Error>?

    /// Bumped by every activation and language reload. The one holding the
    /// latest number owns `AppState`; anything older that finishes late drops
    /// its result instead of committing it.
    ///
    /// This replaced a chain in which each activation awaited the previous
    /// one's result, and the reason is the failure that chain produced: nothing
    /// under `load(_:)` has a timeout of its own. FluidAudio fetches on
    /// URLSession's defaults, where `timeoutIntervalForResource` is seven days,
    /// so on a network that blackholes huggingface.co the load neither returns
    /// nor throws. Every later pick then queued behind it forever — the app sat
    /// on "Loading model…", the picker moved and did nothing, and quitting was
    /// the only way out. Cancelling comes first, but a wedged URLSession need
    /// not honour cancellation, so correctness cannot depend on the old task
    /// ever finishing. A generation can be checked without waiting for one.
    private static var activationGeneration = 0

    /// How long a load may go without a single byte landing on disk before the
    /// app stops presenting it as progress.
    ///
    /// Generous on purpose: it is measured between samples of the model folder,
    /// so any live download keeps resetting it, and only something genuinely
    /// stuck — a blocked host, a dead connection — runs it out. It does not
    /// abort the load, which cannot be made to return; it stops the UI from
    /// insisting everything is fine.
    private static let stallWindow: Duration = .seconds(90)

    /// How often the watchdog samples. Each sample walks one model directory
    /// off the main actor.
    private static let stallSampleInterval: Duration = .seconds(10)

    /// Load `model` and make it the active model. If a model is already active it
    /// keeps serving until the swap; on failure the previous model stays active.
    /// Throws so callers (Settings) can surface the error; launch can ignore it —
    /// state and a user notification are handled here either way.
    static func activate(_ model: AppState.WhisperModel) async throws {
        // A newer choice supersedes the one in flight instead of queueing
        // behind it. Cancel it — a load that checks for cancellation stops
        // here — but do not wait for it: see `activationGeneration` for why
        // waiting is the thing that wedged the app. The generation makes the
        // two safe to overlap; whichever is newest is the one allowed to write.
        currentActivation?.cancel()
        activationGeneration &+= 1
        let generation = activationGeneration
        let task = Task { try await performActivation(model, generation: generation) }
        currentActivation = task
        try await task.value
    }

    /// Bring a model up at launch, without ever starting a download nobody
    /// asked for.
    ///
    /// Launch is the one activation the user did not initiate, and until this
    /// existed it would happily spend 600 MB and several minutes on a model
    /// that was merely *recorded* — leaving the app unable to dictate the whole
    /// time, with no picker able to rescue it because the choice it would make
    /// queued behind the very download it was trying to escape. That is exactly
    /// what a Nemotron preference arriving from another Mac produced.
    ///
    /// The preference is left alone: `selectedWhisperModel` is what the user
    /// asked for and Settings keeps showing it, with a Download button next to
    /// it. Only what runs *now* is redirected.
    static func activateAtLaunch() async {
        let state = AppState.shared
        let preferred = state.selectedWhisperModel
        // Closure literal, not the function value: `isReadyToServe` is
        // main-actor isolated and `filter` takes a plain closure, so passing it
        // by reference would strip the isolation the compiler is right to
        // insist on. The literal inherits this context's instead.
        let ready = Set(AppState.WhisperModel.selectable.filter { ModelAvailability.isReadyToServe($0) })
        let model = launchModel(preferred: preferred, ready: ready)
        if model != preferred {
            PushLogger.log("""
                ModelLoader: \(preferred.rawValue) cannot serve without a download — \
                launching on \(model.rawValue) instead
                """)
        }
        try? await activate(model)
    }

    /// Which model launch should actually load, given the saved preference and
    /// what is ready to run right now.
    ///
    /// Rules, in order: the preference if it can run; otherwise the default
    /// (Parakeet Unified) if it is on disk; otherwise anything else that is, in
    /// the settings list's order, which puts the engine needing no download at
    /// all last rather than first. If nothing is ready — a fresh install — the
    /// preference is returned and its download is the one legitimate unattended
    /// one, because there is no app without it.
    ///
    /// `ready` is passed in rather than read from disk here, and holds only
    /// models this Mac can actually select — so a preference for an engine this
    /// OS is too old for (a synced `apple-speech` on macOS 15) is treated as
    /// unavailable rather than loaded into a guaranteed failure. `nonisolated`
    /// and parameterised so the decision can be tested without a disk full of
    /// models, exactly like `languageChangeNeedsReload`.
    nonisolated static func launchModel(
        preferred: AppState.WhisperModel,
        ready: Set<AppState.WhisperModel>
    ) -> AppState.WhisperModel {
        if ready.contains(preferred) { return preferred }
        let fallbacks = [AppState.WhisperModel.parakeetUnified] + AppState.WhisperModel.selectable
        for candidate in fallbacks where candidate != preferred && ready.contains(candidate) {
            return candidate
        }
        // Nothing to fall back on. Download the preference if it is one this Mac
        // can run, and the default otherwise — a first launch has to fetch
        // something or there is no app.
        return AppState.WhisperModel.selectable.contains(preferred) ? preferred : .parakeetUnified
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
    /// Throws on failure. There is still no useful "undo the user's language" —
    /// the choice is recorded and `AppState` carries the outcome — but the
    /// caller now draws a progress bar for this, and a bar that cannot report a
    /// failure only replaces a silent stall with a spinner that lies. Crossing
    /// vocab groups fetches ~600 MB, so this is a failure worth showing.
    static func reloadForLanguageChange(_ model: AppState.WhisperModel) async throws {
        let state = AppState.shared
        guard languageChangeNeedsReload(changed: model,
                                        activeModel: state.activeModel,
                                        isModelReady: state.isModelReady) else { return }

        // Takes the same generation as `activate`, for the same reason: a
        // language reload racing a model switch would otherwise let the slower
        // of the two commit last and leave the engine serving a language nobody
        // asked for. It supersedes rather than queues — waiting on an
        // activation that may never return is what this stopped doing.
        currentActivation?.cancel()
        activationGeneration &+= 1
        let generation = activationGeneration
        let task = Task { try await performLanguageReload(model, generation: generation) }
        currentActivation = task
        try await task.value
    }

    /// Unload the active model and mark the app as having no model (used when
    /// the user deletes the active model's files).
    static func deactivate() async {
        let state = AppState.shared
        // Nothing already in flight may commit after this. The user has just
        // deleted the files a load was reading, and a late success would report
        // a model that is no longer on disk as ready to dictate with.
        currentActivation?.cancel()
        activationGeneration &+= 1
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

    private static func performActivation(_ model: AppState.WhisperModel, generation: Int) async throws {
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

        let watchdog = stallWatchdog(for: model, generation: generation, hadModel: hadModel)
        defer { watchdog.cancel() }

        do {
            try await load(model)
        } catch {
            guard generation == activationGeneration, !(error is CancellationError) else {
                // Superseded — by a newer pick, or by this one being cancelled
                // for it. A different activation owns `AppState` now, so this
                // touches none of it: reporting a failure here would paint
                // stale news over live state, and put a red line under a row
                // the user has already left. The engine is dropped so a load
                // that got far enough to be resident does not linger.
                PushLogger.log("ModelLoader: activation of \(model.rawValue) superseded")
                if model.engineType != state.activeModel.engineType { await unload(model) }
                throw CancellationError()
            }
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

        // The same check on the way out of a *successful* load: a wedged fetch
        // that finally returns half an hour later must not shoulder aside the
        // model the user switched to in the meantime.
        guard generation == activationGeneration else {
            PushLogger.log("ModelLoader: discarding a superseded \(model.rawValue) load")
            if model.engineType != state.activeModel.engineType { await unload(model) }
            throw CancellationError()
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
    private static func performLanguageReload(_ model: AppState.WhisperModel, generation: Int) async throws {
        let state = AppState.shared

        // The engine this reload is about may not be the one running any more.
        guard state.activeModel == model else { return }

        state.isWarmingUp = true
        state.statusMessage = "Loading \(model.shortName)…"
        PushLogger.log("ModelLoader: Reloading \(model.rawValue) for a language change...")
        let loadStart = Date()

        let watchdog = stallWatchdog(for: model, generation: generation, hadModel: state.isModelReady)
        defer { watchdog.cancel() }

        do {
            try await load(model)
        } catch {
            guard generation == activationGeneration, !(error is CancellationError) else {
                // A model switch overtook this reload. It reports its own
                // outcome and decides what is loaded now — "Model failed to
                // load" here would be both wrong and louder than the truth.
                PushLogger.log("ModelLoader: language reload of \(model.rawValue) superseded")
                throw CancellationError()
            }
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

        guard generation == activationGeneration else {
            PushLogger.log("ModelLoader: discarding a superseded \(model.rawValue) language reload")
            throw CancellationError()
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

    /// Watches a load that has not come back yet, and says so once the model
    /// folder has gone `stallWindow` without a byte landing in it.
    ///
    /// It cannot stop the load: a URLSession stuck on a host that never answers
    /// returns when it returns, and nothing here gets to decide otherwise. What
    /// it can stop is the app implying progress it is not making. Left on
    /// "Loading model…" the pill reads as "nearly there" indefinitely, which is
    /// how a wedged first launch on a locked-down network gets mistaken for a
    /// slow one — and why the only fix anyone finds is quitting.
    ///
    /// Only the launch case (`hadModel == false`) is marked unavailable: with a
    /// previous model still serving, dictation works and the pill must not claim
    /// otherwise. If the load does eventually land, `performActivation` clears
    /// all of this on its way through.
    ///
    /// The window is measured between samples of the folder, so a slow download
    /// keeps resetting it and only a dead one runs it out — the same bytes the
    /// Settings pane already draws its progress bar from, which is the evidence
    /// that a live fetch grows this directory as it goes.
    private static func stallWatchdog(
        for model: AppState.WhisperModel,
        generation: Int,
        hadModel: Bool
    ) -> Task<Void, Never> {
        // Apple Speech is exempt: the OS owns that install, takes as long as it
        // takes, and reports its own state in Settings. There are no files of
        // ours to watch and nothing here would be true of it.
        guard let folder = ModelAvailability.folder(for: model) else { return Task {} }

        return Task { @MainActor in
            var lastSize = await measure(folder)
            var quiet: Duration = .zero
            while quiet < stallWindow {
                try? await Task.sleep(for: stallSampleInterval)
                if Task.isCancelled { return }
                let size = await measure(folder)
                if size == lastSize {
                    quiet += stallSampleInterval
                } else {
                    lastSize = size
                    quiet = .zero
                }
            }
            guard !Task.isCancelled, generation == activationGeneration else { return }

            let state = AppState.shared
            PushLogger.log("ModelLoader: \(model.rawValue) has made no progress in \(stallWindow) — reporting it stuck")
            state.isWarmingUp = false
            if !hadModel {
                state.modelUnavailable = true
                state.statusMessage = "Model unavailable"
            }
            NotificationManager.shared.showError(
                title: "\(model.shortName) is not loading",
                message: """
                    Nothing has arrived for a while. If this Mac is on a network \
                    that blocks huggingface.co the download cannot start — pick \
                    another model in PUSH's Settings.
                    """)
        }
    }

    /// One sample for the watchdog, taken off the main actor — walking a model
    /// directory on it is how this app loses its event tap.
    private static func measure(_ folder: URL) async -> Double {
        await Task.detached(priority: .utility) {
            ModelAvailability.directorySize(at: folder)
        }.value
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
