import Foundation

/// TEMPORARY STUB — pending Task 2 of the media-pause-dictation plan.
///
/// This will be replaced with a real dlopen/dlsym bridge into the private
/// MediaRemote.framework (MRMediaRemoteSendCommand /
/// MRMediaRemoteGetNowPlayingInfo) so `MediaPauseController` can pause/resume
/// whatever's actually playing. Until then, `load()` returns `nil`, which
/// makes `MediaPauseController.shared` a no-op (matches its existing nil
/// fallback), so nothing regresses — dictation just doesn't pause media yet.
enum MediaRemoteBridge {
    struct Handle {
        let sendCommand: (Int) -> Bool
        let fetchRate: (@escaping (Double?) -> Void) -> Void
    }

    static func load() -> Handle? {
        nil
    }
}
