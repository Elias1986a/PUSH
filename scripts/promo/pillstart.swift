import AVFoundation
import CoreGraphics
// pillstart <movie> <from> <to>: brightness of the bottom-centre strip (where
// the pill appears) every 0.05 s, to find the frame the pill shows up.
let a = CommandLine.arguments
let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: a[1])))
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
gen.maximumSize = CGSize(width: 640, height: 360)
var t = Double(a[2])!
while t <= Double(a[3])! {
    if let img = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil),
       let strip = img.cropping(to: CGRect(x: img.width / 5, y: img.height - 24, width: img.width * 3 / 5, height: 24)) {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .medium
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        print(String(format: "%.2f %3d", t, (Int(p[0]) + Int(p[1]) + Int(p[2])) / 3))
    }
    t += 0.05
}
