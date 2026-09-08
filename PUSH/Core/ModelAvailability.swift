import Foundation
import PUSHCore

/// Which speech models are on disk and ready to serve.
///
/// Shared by the Models settings pane and the menu bar popover. The popover
/// needs it to answer a question the settings pane already answered: a model
/// switcher that offered an undownloaded model would start a multi-hundred
/// megabyte download from a menu click, which is not a thing a menu should be
/// able to do.
enum ModelAvailability {

    /// True when `model` can be activated without downloading anything.
    static func isDownloaded(_ model: WhisperModel) -> Bool {
        switch model.engineType {
        case .parakeet: return ParakeetEngine.isModelDownloaded()
        case .parakeetUnified: return ParakeetUnifiedEngine.isModelDownloaded()
        case .parakeetStreaming: return ParakeetStreamingEngine.isModelDownloaded()
        case .nemotronMultilingual: return NemotronMultilingualEngine.isModelDownloaded()
        case .appleSpeech:
            // Nothing for us to download — the system installs on demand.
            return true
        }
    }

    /// Every selectable model already on disk. Touches the filesystem, so call
    /// it on an explicit refresh rather than from a SwiftUI `body`.
    static func downloaded() -> Set<WhisperModel> {
        Set(WhisperModel.selectable.filter(isDownloaded))
    }

    /// True when `model` can be activated *in the language it would actually
    /// run in* without downloading anything.
    ///
    /// A stricter question than `isDownloaded`, and only Nemotron can tell the
    /// two apart: it ships one ~600 MB build per script group, and
    /// `isDownloaded()` answers "at least one of them is here". A Mac holding
    /// the Latin build with Japanese selected passes that check and then spends
    /// 600 MB on the way up — which is fine when the user just pressed
    /// Download, and is not fine at launch, where nobody asked for anything.
    ///
    /// Main-actor because the saved language lives on `AppState`; the
    /// filesystem checks underneath are cheap `fileExists` calls.
    @MainActor
    static func isReadyToServe(_ model: WhisperModel) -> Bool {
        guard model == .nemotronMultilingual else { return isDownloaded(model) }
        return NemotronMultilingualEngine.isModelDownloaded(
            for: AppState.shared.language(for: model).code)
    }
}
