import Foundation

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

    // MARK: - Private

    private static func performActivation(_ model: AppState.WhisperModel) async throws {
        let state = AppState.shared
        if state.isModelReady, state.activeModel == model {
            return
        }

        let previous = state.activeModel
        let hadModel = state.isModelReady
        state.isWarmingUp = true
        state.statusMessage = hadModel ? "Loading \(model.displayName)…" : "Loading AI model…"
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
        case .moonshine: try await MoonshineEngine.shared.loadModel(model)
        case .parakeet: try await ParakeetEngine.shared.loadModel()
        case .parakeetUnified: try await ParakeetUnifiedEngine.shared.loadModel()
        case .parakeetStreaming: try await ParakeetStreamingEngine.shared.loadModel()
        case .whisperKit: try await WhisperEngine.shared.loadModel(model)
        case .appleSpeech:
            guard #available(macOS 26, *) else { throw ModelLoaderError.requiresNewerSystem }
            try await AppleSpeechEngine.shared.loadModel()
        }
    }

    private static func unload(_ model: AppState.WhisperModel) async {
        switch model.engineType {
        case .moonshine: await MoonshineEngine.shared.unloadModel()
        case .parakeet: await ParakeetEngine.shared.unloadModel()
        case .parakeetUnified: await ParakeetUnifiedEngine.shared.unloadModel()
        case .parakeetStreaming: await ParakeetStreamingEngine.shared.unloadModel()
        case .whisperKit: await WhisperEngine.shared.unloadModel()
        case .appleSpeech:
            if #available(macOS 26, *) { await AppleSpeechEngine.shared.unloadModel() }
        }
    }

    private static func warmup(_ model: AppState.WhisperModel) async {
        switch model.engineType {
        case .moonshine: await MoonshineEngine.shared.warmupInference()
        case .parakeet: await ParakeetEngine.shared.warmup()
        case .parakeetUnified: await ParakeetUnifiedEngine.shared.warmup()
        case .parakeetStreaming: await ParakeetStreamingEngine.shared.warmup()
        case .whisperKit: await WhisperEngine.shared.warmupInference()
        case .appleSpeech:
            if #available(macOS 26, *) { await AppleSpeechEngine.shared.warmup() }
        }
    }
}

// MARK: - Errors

enum ModelLoaderError: LocalizedError {
    /// Reachable only from a saved preference that outlived a downgrade — the picker
    /// filters this model out on systems that can't run it.
    case requiresNewerSystem

    var errorDescription: String? {
        switch self {
        case .requiresNewerSystem:
            return "Apple Speech requires macOS 26 or later"
        }
    }
}
