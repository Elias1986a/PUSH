import AVFoundation
// webexport <in.mp4> <out.mp4>: 1280x720 H.264/AAC for the website.
let a = CommandLine.arguments
let sem = DispatchSemaphore(value: 0)
Task {
    let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
    let out = URL(fileURLWithPath: a[2]); try? FileManager.default.removeItem(at: out)
    let e = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720)!
    e.shouldOptimizeForNetworkUse = true
    do { try await e.export(to: out, as: .mp4); print("ok") } catch { print("failed:", error) }
    sem.signal()
}
sem.wait()
