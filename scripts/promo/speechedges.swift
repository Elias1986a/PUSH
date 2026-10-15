import AVFoundation
// Where speech starts and ends in an audio file (first/last 20 ms window above -40 dBFS).
let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
try file.read(into: buf)
let d = buf.floatChannelData![0], n = Int(buf.frameLength), sr = file.processingFormat.sampleRate
let win = Int(sr * 0.02)
var first = -1.0, last = -1.0
var i = 0
while i + win < n {
    var s: Float = 0; for j in i..<(i + win) { s += d[j] * d[j] }
    let db = 10 * log10(Double(s) / Double(win) + 1e-12)
    if db > -40 { if first < 0 { first = Double(i) / sr }; last = Double(i + win) / sr }
    i += win
}
print(String(format: "speech from %.2f s to %.2f s of %.2f s", first, last, Double(n) / sr))
