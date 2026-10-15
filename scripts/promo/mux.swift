import AVFoundation
// mux <video.mov> <audio> <offset s> <audio length s, 0 = all> <out.mp4> [video start s] [video end s]
// Offset is in the ORIGINAL video's time; the optional start/end trim the picture.
// Lays the audio under the screen recording, starting at <offset>, with a
// 0.2 s fade at the end of a cut so it does not click.
let a = CommandLine.arguments
let video = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let audio = AVURLAsset(url: URL(fileURLWithPath: a[2]))
let offset = CMTime(seconds: Double(a[3])! - (a.count > 6 ? Double(a[6])! : 0), preferredTimescale: 600)
let sem = DispatchSemaphore(value: 0)
Task {
    let comp = AVMutableComposition()
    let full = try await video.load(.duration)
    let start = CMTime(seconds: a.count > 6 ? Double(a[6])! : 0, preferredTimescale: 600)
    let end = a.count > 7 ? CMTime(seconds: Double(a[7])!, preferredTimescale: 600) : full
    let vDur = CMTimeSubtract(end, start)
    let vTrack = try await video.loadTracks(withMediaType: .video).first!
    let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try cv.insertTimeRange(CMTimeRange(start: start, duration: vDur), of: vTrack, at: .zero)
    cv.preferredTransform = try await vTrack.load(.preferredTransform)
    let aTrack = try await audio.loadTracks(withMediaType: .audio).first!
    var aDur = try await audio.load(.duration)
    if Double(a[4])! > 0 { aDur = CMTime(seconds: Double(a[4])!, preferredTimescale: 600) }
    aDur = CMTimeMinimum(aDur, CMTimeSubtract(vDur, offset))
    let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try ca.insertTimeRange(CMTimeRange(start: .zero, duration: aDur), of: aTrack, at: offset)
    let params = AVMutableAudioMixInputParameters(track: ca)
    let fade = CMTime(seconds: 0.2, preferredTimescale: 600)
    params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: CMTimeSubtract(CMTimeAdd(offset, aDur), fade), duration: fade))
    let mix = AVMutableAudioMix(); mix.inputParameters = [params]
    let out = URL(fileURLWithPath: a[5]); try? FileManager.default.removeItem(at: out)
    let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
    export.audioMix = mix
    try await export.export(to: out, as: .mp4)
    print("wrote \(a[5]) — video \(String(format: "%.1f", vDur.seconds)) s, audio \(String(format: "%.1f", aDur.seconds)) s from \(a[3]) s")
    sem.signal()
}
sem.wait()
