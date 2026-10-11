import Foundation
import PUSHCore

/// Keeps `LlamaEngine.shared` in step with the Type switch and the chosen
/// model: loaded while Type is on and its model is on disk, unloaded
/// otherwise. Only this type loads or unloads the engine.
///
/// Calls never wait on each other: each one bumps `generation`, and a load
/// that finishes after a newer call simply unloads again.
@MainActor
enum TypingEngineLoader {
    private static var generation = 0
    private static var loaded: TypingModel?
    /// What the newest call is bringing in (nil: unloading), so a repeat call
    /// does not start the same load twice.
    private static var target: TypingModel??

    static func apply() {
        generation &+= 1
        let current = generation
        let state = AppState.shared
        let wanted: TypingModel? = state.typeEnabled && TypingModelStore.shared.onDisk.contains(state.selectedTypingModel)
            ? state.selectedTypingModel : nil
        if let target, target == wanted { return }
        if target == nil, wanted == loaded { return }
        target = .some(wanted)
        state.typingModelReady = false
        Task {
            if let model = wanted {
                let start = Date()
                do {
                    try await LlamaEngine.shared.load(path: TypingModelStore.url(for: model).path)
                    // One tiny completion so the GPU code is compiled now, in
                    // the background, not on the user's first keystroke.
                    for try await _ in await LlamaEngine.shared.complete(prompt: "Hello", maxTokens: 1) {}
                } catch {
                    PushLogger.log("TypingEngineLoader: loading \(model.rawValue) failed: \(error)")
                    await LlamaEngine.shared.unload()
                    if current == generation { loaded = nil; target = nil }
                    return
                }
                guard current == generation else { return }
                loaded = model
                target = nil
                state.typingModelReady = true
                PushLogger.log("TypingEngineLoader: \(model.rawValue) ready in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
            } else {
                await LlamaEngine.shared.unload()
                guard current == generation else { return }
                loaded = nil
                target = nil
                PushLogger.log("TypingEngineLoader: unloaded")
            }
        }
    }

    /// Before deleting a model's file.
    static func unloadIfLoaded(_ model: TypingModel) async {
        guard loaded == model || target == .some(model) else { return }
        generation &+= 1
        loaded = nil
        target = nil
        AppState.shared.typingModelReady = false
        await LlamaEngine.shared.unload()
        PushLogger.log("TypingEngineLoader: unloaded \(model.rawValue) for deletion")
    }
}
