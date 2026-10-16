import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

// A dictation take recorded as its own element, at full Retina resolution in
// ProRes 422 HQ (screencapture -v compresses hard: ~1-2 Mbps). In one process,
// so every time below shares the host clock:
//   1. records the screen region (points, top-left origin of the main display),
//   2. after --lead s holds Left Option (the PUSH-to-talk key),
//   3. 0.3 s later plays --audio, holds for its length + --after s (the live
//      words run ~1.5 s behind the voice: 2.5 lets every word show), lets go,
//   4. keeps recording --tail s (the pill closing, the text landing).
// Prints when the key went down, the voice started and the key came up, in
// seconds of the movie, so the voice can be laid back under it exactly.
//
//   pilltake <x> <y> <w> <h> <out.mov> --audio <file> [--lead 1.0] [--after 2.5] [--tail 3.0]
//   pilltake --probe        holds Option 2.5 s and prints PUSH's window frames
//
// Build: swiftc -O pilltake.swift -o /tmp/pilltake (outside the repo).

let args = CommandLine.arguments
func opt(_ name: String, _ fallback: Double) -> Double {
    guard let i = args.firstIndex(of: name), i + 1 < args.count, let v = Double(args[i + 1]) else { return fallback }
    return v
}
func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

/// Left Option as a real press reports it (see holdoption.swift).
func option(_ down: Bool) {
    let src = CGEventSource(stateID: .hidSystemState)
    let e = CGEvent(keyboardEventSource: src, virtualKey: 58, keyDown: down)!
    e.type = .flagsChanged
    e.flags = down ? CGEventFlags(rawValue: 0x80120) : []
    e.post(tap: .cghidEventTap)
}

if args.contains("--probe") {
    option(true)
    Thread.sleep(forTimeInterval: 1.5)
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowOwnerName as String] as? String) == "PUSH" {
        print("PUSH window", w[kCGWindowBounds as String] ?? "", "layer", w[kCGWindowLayer as String] ?? "")
    }
    Thread.sleep(forTimeInterval: 1.0)
    option(false)
    exit(0)
}

guard args.count >= 6, let x = Double(args[1]), let y = Double(args[2]), let w = Double(args[3]), let h = Double(args[4]) else {
    print("usage: pilltake <x> <y> <w> <h> <out.mov> --audio <file> [--lead s] [--after s] [--tail s] | --probe")
    exit(64)
}
let out = URL(fileURLWithPath: args[5])
guard let ai = args.firstIndex(of: "--audio"), ai + 1 < args.count else { print("--audio <file> required"); exit(64) }
let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: args[ai + 1]))
player.prepareToPlay()
let lead = opt("--lead", 1.0), after = opt("--after", 2.5), tail = opt("--tail", 3.0)

final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var start: Double?
    var frames = 0
    init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes422HQ,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let pts = sb.presentationTimeStamp
        if start == nil {
            start = pts.seconds
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
        }
        if input.isReadyForMoreMediaData, input.append(sb) { frames += 1 }
    }
}

let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { print("no main display"); exit(1) }
let filter = SCContentFilter(display: display, excludingWindows: [])
let scale = Double(filter.pointPixelScale)
let config = SCStreamConfiguration()
config.sourceRect = CGRect(x: x, y: y, width: w, height: h)
config.width = Int(w * scale)
config.height = Int(h * scale)
config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
config.pixelFormat = kCVPixelFormatType_32BGRA
config.colorSpaceName = CGColorSpace.sRGB
config.showsCursor = false
config.queueDepth = 8

let rec = try Recorder(url: out, width: config.width, height: config.height)
let stream = SCStream(filter: filter, configuration: config, delegate: nil)
try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "pilltake"))
try await stream.startCapture()

try await Task.sleep(for: .seconds(lead))
let keyDown = hostNow()
option(true)
try await Task.sleep(for: .seconds(0.3))
let voiceAt = hostNow()
player.play()
try await Task.sleep(for: .seconds(player.duration + after))
let keyUp = hostNow()
option(false)
try await Task.sleep(for: .seconds(tail))
try await stream.stopCapture()
rec.input.markAsFinished()
await rec.writer.finishWriting()

guard let t0 = rec.start else { print("no frames captured"); exit(1) }
print(String(format: "%@  %dx%d @%.0fx, %d frames", out.lastPathComponent, config.width, config.height, scale, rec.frames))
print(String(format: "key down %.3f s · voice starts %.3f s · key up %.3f s (seconds into the movie)", keyDown - t0, voiceAt - t0, keyUp - t0))
