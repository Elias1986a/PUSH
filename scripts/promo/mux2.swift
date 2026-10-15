import AVFoundation
// mux2 <video> <audio> <start> <stretchFrom> <release> <end> <extra s> <audio offset in output> <out>
// Cuts [start,end] of the video, plays [stretchFrom,release] slower by <extra>
// seconds, and lays the whole audio file at <audio offset> in the result.
let a = CommandLine.arguments
func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }
let (start, from, release, end, extra, aoff) = (Double(a[3])!, Double(a[4])!, Double(a[5])!, Double(a[6])!, Double(a[7])!, Double(a[8])!)
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let video = AVURLAsset(url: URL(fileURLWithPath: a[1])), audio = AVURLAsset(url: URL(fileURLWithPath: a[2]))
        let comp = AVMutableComposition()
        let vt = try await video.loadTracks(withMediaType: .video).first!
        let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try cv.insertTimeRange(CMTimeRange(start: t(start), end: t(end)), of: vt, at: .zero)
        cv.preferredTransform = try await vt.load(.preferredTransform)
        comp.scaleTimeRange(CMTimeRange(start: t(from - start), duration: t(release - from)), toDuration: t(release - from + extra))
        let at = try await audio.loadTracks(withMediaType: .audio).first!
        let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try ca.insertTimeRange(CMTimeRange(start: .zero, duration: try await audio.load(.duration)), of: at, at: t(aoff))
        let out = URL(fileURLWithPath: a[9]); try? FileManager.default.removeItem(at: out)
        let e = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
        try await e.export(to: out, as: .mp4)
        print("wrote \(a[9]), \(String(format: "%.2f", comp.duration.seconds)) s")
    } catch { print("failed:", error) }
    sem.signal()
}
sem.wait()
