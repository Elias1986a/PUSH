import AVFoundation
import AppKit
// frames <movie> <out-prefix> <t1> <t2> …  — saves a JPEG at each time (seconds).
let args = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let gen = AVAssetImageGenerator(asset: asset)
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
gen.maximumSize = CGSize(width: 1100, height: 1100)
for t in args.dropFirst(3) {
    let time = CMTime(seconds: Double(t)!, preferredTimescale: 600)
    guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { print("no frame at", t); continue }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])!.write(to: URL(fileURLWithPath: "\(args[2])-\(t).jpg"))
    print("saved \(args[2])-\(t).jpg")
}
