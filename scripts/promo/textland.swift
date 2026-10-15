import AVFoundation
import CoreGraphics
// Brightness of the note's first text line every 0.02 s: shows the frame the text lands.
// textland <movie> <from> <to> [line top, % of height; 18 = the live-preview frame]
let a = CommandLine.arguments
let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: a[1])))
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
gen.maximumSize = CGSize(width: 640, height: 360)
let top = a.count > 4 ? Int(a[4])! : 18
var t = Double(a[2])!
while t <= Double(a[3])! {
    if let img = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil),
       let line = img.cropping(to: CGRect(x: img.width / 8, y: img.height * top / 100, width: img.width * 3 / 4, height: img.height / 20)) {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(line, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        print(String(format: "%.2f %3d", t, (Int(p[0]) + Int(p[1]) + Int(p[2])) / 3))
    }
    t += 0.02
}
