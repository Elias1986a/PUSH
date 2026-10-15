import AVFoundation
// trimexport <in> <out.mp4> <start s> <end s> [web] — cuts a clip; "web" = 1280x720.
let a = CommandLine.arguments
let sem = DispatchSemaphore(value: 0)
Task {
    let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
    let out = URL(fileURLWithPath: a[2]); try? FileManager.default.removeItem(at: out)
    let e = AVAssetExportSession(asset: asset, presetName: a.count > 5 ? AVAssetExportPreset1280x720 : AVAssetExportPresetHighestQuality)!
    e.timeRange = CMTimeRange(start: CMTime(seconds: Double(a[3])!, preferredTimescale: 600), end: CMTime(seconds: Double(a[4])!, preferredTimescale: 600))
    e.shouldOptimizeForNetworkUse = true
    do { try await e.export(to: out, as: .mp4); print("wrote", a[2]) } catch { print("failed:", error) }
    sem.signal()
}
sem.wait()
