import AVFoundation
// Records the default input for N seconds and prints the RMS level per second.
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "6") ?? 6
let engine = AVAudioEngine()
let input = engine.inputNode
let format = input.outputFormat(forBus: 0)
print("input format:", format.sampleRate, "Hz", format.channelCount, "ch")
var sum: Double = 0, count = 0, perSecond: [Double] = []
let lock = NSLock()
input.installTap(onBus: 0, bufferSize: 4096, format: format) { buf, _ in
    guard let d = buf.floatChannelData?[0] else { return }
    lock.lock(); for i in 0..<Int(buf.frameLength) { sum += Double(d[i] * d[i]) }; count += Int(buf.frameLength)
    if Double(count) >= format.sampleRate { perSecond.append((sum / Double(count)).squareRoot()); sum = 0; count = 0 }
    lock.unlock()
}
try engine.start()
Thread.sleep(forTimeInterval: seconds)
engine.stop()
print("rms per second:", perSecond.map { String(format: "%.4f", $0) }.joined(separator: " "))
