import Foundation

/// Thin dlopen/dlsym bridge to the private MediaRemote.framework — the same
/// mechanism behind Control Center's Now Playing widget and hardware media
/// keys. Loaded dynamically (never linked) since it's unversioned and could
/// disappear in a future macOS release; if so, `load()` returns nil and
/// MediaPauseController silently disables itself for the session.
enum MediaRemoteBridge {
    struct Handle {
        let sendCommand: (Int) -> Bool
        let fetchRate: (@escaping (Double?) -> Void) -> Void
    }

    private typealias SendCommandFn = @convention(c) (Int, AnyObject?) -> Bool
    private typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void

    static func load() -> Handle? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else {
            PushLogger.log("MediaRemoteBridge: framework unavailable, media pause disabled")
            return nil
        }

        guard let sendPtr = dlsym(handle, "MRMediaRemoteSendCommand"),
              let infoPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            PushLogger.log("MediaRemoteBridge: expected symbols not found, media pause disabled")
            return nil
        }

        let sendCommand = unsafeBitCast(sendPtr, to: SendCommandFn.self)
        let getNowPlayingInfo = unsafeBitCast(infoPtr, to: GetNowPlayingInfoFn.self)

        return Handle(
            sendCommand: { command in sendCommand(command, nil) },
            fetchRate: { completion in
                getNowPlayingInfo(DispatchQueue.main) { info in
                    completion(info?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double)
                }
            }
        )
    }
}
