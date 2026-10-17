import AppKit
import AVFoundation
import SwiftUI

/// The number a user feels: how long after letting go of the key the text is on
/// screen, timed the same way for every dictation app.
///
/// The engine comparison cannot see it. It feeds audio straight into the engines
/// and reads Wispr's own server timing, so the paste, the target app and anything
/// holding the dictation app's main thread are all outside it. Until 2026-10-14
/// the website quoted that engine number (0.04 s) while text landed ~0.35 s after
/// release; measuring this way found the two causes (`VoiceGlow`'s fade and the
/// audio engine's stop, both on the main thread).
///
/// Each run: clear the box, hold the app's key, play the recording through the
/// speakers, let go as the speech ends, and time from the release to the first
/// change in the box. The key is synthetic, so this app needs Accessibility.
enum DictationTarget: String, CaseIterable, Identifiable, Codable {
    case pushtype = "PUSHTYPE"
    case wispr = "Wispr Flow"
    var id: String { rawValue }

    /// The user's setup: PUSHTYPE on Left Option, Wispr Flow on Left Control.
    var defaultKey: HoldKey { self == .pushtype ? .leftOption : .leftControl }

    var bundleID: String { self == .pushtype ? "com.push.voicetotext" : "com.electron.wispr-flow" }

    /// The pause before the next hold. Wispr Flow returns nothing for a hold
    /// started within ~10 s of its last paste (2026-10-16: with 2 s, every run
    /// after a success came back empty).
    var gap: Duration { self == .pushtype ? .seconds(2) : .seconds(10) }

    /// The copy that is running, which is the one being measured.
    var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    var version: String? {
        running?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
    }

    /// PUSHTYPE's chosen speech model, read from its preferences. It is only
    /// the model serving the run if PUSHTYPE was relaunched after it was set.
    var model: String? {
        guard self == .pushtype else { return nil }
        return CFPreferencesCopyAppValue("selectedWhisperModel" as CFString, bundleID as CFString) as? String
    }
}

/// A modifier held like a finger on it. Flags as a real press reports them:
/// the modifier, its side bit and the non-coalesced bit. Released with `[]`, or
/// the modifier stays stuck and Tab turns into the app switcher.
enum HoldKey: String, CaseIterable, Identifiable {
    case leftOption = "Left Option"
    case rightOption = "Right Option"
    case leftControl = "Left Control"
    var id: String { rawValue }

    var keyCode: CGKeyCode {
        switch self { case .leftOption: 58; case .rightOption: 61; case .leftControl: 59 }
    }
    var downFlags: UInt64 {
        switch self { case .leftOption: 0x80120; case .rightOption: 0x80140; case .leftControl: 0x40101 }
    }

    /// The generic flag the system's modifier state reports for this key.
    var generic: CGEventFlags { self == .leftControl ? .maskControl : .maskAlternate }

    /// A synthetic press lives only in the session's modifier state, and any
    /// real key pressed meanwhile (typing in another window) resets it, which
    /// PUSHTYPE's release watchdog then reads as the key coming up. A finger
    /// would still be on the key, so put it back down; never re-pressed while
    /// the state still shows it, so an app never sees an extra press.
    func stillHeld() {
        if !CGEventSource.flagsState(.combinedSessionState).contains(generic) { post(down: true) }
    }

    func post(down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = down ? CGEventFlags(rawValue: downFlags) : []
        event.post(tap: .cghidEventTap)
    }
}

struct EndToEndRun: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var target: DictationTarget
    var audioFile: String
    var heldSeconds: Double
    /// Nil when nothing arrived within the wait.
    var releaseToTextMs: Double?
    /// Last change in the box: differs from the first when an app pastes in
    /// pieces or rewrites what it pasted.
    var releaseToSettledMs: Double?
    var text: String
    /// The window lost focus during the hold (someone using the Mac): the
    /// key may have been released early and the paste may have gone elsewhere.
    /// Left out of the medians.
    var interrupted: Bool? = nil
    var appVersion: String? = nil
    /// PUSHTYPE's speech model (`parakeet-streaming`, `parakeet-ultra`).
    var model: String? = nil
}

@MainActor
@Observable
final class EndToEndModel {
    var target: DictationTarget = .pushtype { didSet { key = target.defaultKey } }
    var key: HoldKey = DictationTarget.pushtype.defaultKey
    var count = 5
    var audioURL: URL? = EndToEndModel.defaultAudio
    var runs: [EndToEndRun] = EndToEndLog.load().reversed()
    var status = ""
    var isRunning = false

    /// The text box the apps paste into. Set by `PasteTarget`.
    weak var textView: NSTextView?
    private var releasedAt: UInt64?
    private var firstChange: UInt64?
    private var lastChange: UInt64?

    /// The promo voice reading the benchmark passage, in the repo.
    static var defaultAudio: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("promo/voice/benchmark-passage-jessica.mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func chooseAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose the recording to play through the speakers."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        audioURL = url
    }

    func textChanged() {
        let now = DispatchTime.now().uptimeNanoseconds
        if releasedAt != nil, firstChange == nil { firstChange = now }
        lastChange = now
    }

    func median(for target: DictationTarget) -> (ms: Double, n: Int)? {
        let values = runs.filter { $0.target == target && $0.interrupted != true }
            .compactMap(\.releaseToTextMs).sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        let ms = values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
        return (ms, values.count)
    }

    func clear() {
        runs.removeAll()
        EndToEndLog.clear()
    }

    func start() {
        run([(target, key, count)])
    }

    /// Unattended: `COMPARE_E2E="pushtype:25,wispr:25"` opens this window,
    /// runs each in turn and quits (exit 1 if a series stopped early).
    /// `scripts/speedtest.sh` drives a whole study with it.
    private var unattended = false

    func runFromEnvironment() {
        guard let spec = ProcessInfo.processInfo.environment["COMPARE_E2E"] else { return }
        unattended = true
        let plan = spec.split(separator: ",").compactMap { item -> (DictationTarget, HoldKey, Int)? in
            let parts = item.split(separator: ":")
            guard let name = parts.first, let n = parts.last.flatMap({ Int($0) }),
                  let target = DictationTarget.allCases.first(where: {
                      $0.rawValue.lowercased().hasPrefix(name.lowercased()) || ($0 == .pushtype && name == "push")
                  })
            else { return nil }
            return (target, target.defaultKey, n)
        }
        run(plan)
    }

    private func finish(_ message: String, failed: Bool) {
        status = message
        isRunning = false
        guard unattended else { return }
        print(failed ? "compare: \(message)" : "compare: done")
        exit(failed ? 1 : 0)
    }

    /// Runs until `count` runs brought text. An empty run is logged and
    /// retried, up to 10 in a series; an interrupted one stops everything.
    private func run(_ plan: [(DictationTarget, HoldKey, Int)]) {
        guard !isRunning, let audioURL, !plan.isEmpty else { return }
        guard AXIsProcessTrusted() else {
            finish("Needs Accessibility to hold the key: System Settings ▸ Privacy & Security ▸ Accessibility ▸ PUSH Compare.", failed: true)
            return
        }
        if let missing = plan.first(where: { $0.0.running == nil })?.0 {
            finish("\(missing.rawValue) isn't running.", failed: true)
            return
        }
        let speechEnd: Double
        do {
            speechEnd = try Self.speechEnd(of: audioURL)
        } catch {
            finish(error.localizedDescription, failed: true)
            return
        }
        isRunning = true
        Task {
            for (target, key, count) in plan {
                var good = 0, empty = 0
                while good < max(count, 1) {
                    guard isRunning else { return }
                    status = "\(target.rawValue): run \(good + 1) of \(count)\(empty > 0 ? ", \(empty) empty" : "") (speech ends at \(speechEnd.formatted(.number.precision(.fractionLength(2)))) s)…"
                    guard let run = await runOnce(target: target, key: key, audioURL: audioURL, speechEnd: speechEnd) else {
                        finish("Stopped: the text box lost focus, so a paste would land somewhere else.", failed: true)
                        return
                    }
                    runs.insert(run, at: 0)
                    EndToEndLog.append(run)
                    if run.interrupted == true {
                        finish("Stopped: another app came to the front during the hold. Leave the Mac alone while this runs.", failed: true)
                        return
                    }
                    if run.releaseToTextMs == nil {
                        empty += 1
                        if empty > 10 {
                            finish("Stopped: \(target.rawValue) brought no text 11 times.", failed: true)
                            return
                        }
                    } else {
                        good += 1
                    }
                    try? await Task.sleep(for: target.gap)
                }
            }
            finish("", failed: false)
        }
    }

    func stop() { isRunning = false }

    private func runOnce(target: DictationTarget, key: HoldKey, audioURL: URL, speechEnd: Double) async -> EndToEndRun? {
        textView?.string = ""
        releasedAt = nil; firstChange = nil; lastChange = nil
        NSApp.activate(ignoringOtherApps: true)
        textView?.window?.makeKeyAndOrderFront(nil)
        textView?.window?.makeFirstResponder(textView)
        try? await Task.sleep(for: .seconds(1))
        guard NSApp.isActive, textView?.window?.isKeyWindow == true else { return nil }

        guard let player = try? AVAudioPlayer(contentsOf: audioURL) else { return nil }
        player.prepareToPlay()
        key.post(down: true)
        let pressed = DispatchTime.now().uptimeNanoseconds
        // A lead-in like a person's: the app has its microphone up before the voice.
        try? await Task.sleep(for: .milliseconds(400))
        player.play()
        // Let go as the voice stops, like someone done talking: the speech end,
        // the output latency, and 0.1 s.
        let releaseAt = DispatchTime.now().uptimeNanoseconds + UInt64((speechEnd + 0.05 + 0.1) * 1e9)
        var interrupted = false
        while DispatchTime.now().uptimeNanoseconds < releaseAt {
            if !(NSApp.isActive && textView?.window?.isKeyWindow == true) { interrupted = true }
            key.stillHeld()
            let left = Double(releaseAt - min(releaseAt, DispatchTime.now().uptimeNanoseconds)) / 1e9
            try? await Task.sleep(for: .seconds(min(0.1, left)))
        }
        releasedAt = DispatchTime.now().uptimeNanoseconds
        key.post(down: false)
        let released = releasedAt!

        // Wait for the text, then for it to settle.
        let deadline = released + 15_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            if let last = lastChange, DispatchTime.now().uptimeNanoseconds - last > 2_000_000_000 { break }
        }
        while player.isPlaying { try? await Task.sleep(for: .milliseconds(50)) }

        func ms(_ t: UInt64?) -> Double? { t.map { Double($0 - released) / 1_000_000 } }
        return EndToEndRun(
            target: target, audioFile: audioURL.lastPathComponent,
            heldSeconds: Double(released - pressed) / 1_000_000_000,
            releaseToTextMs: ms(firstChange), releaseToSettledMs: ms(lastChange),
            text: textView?.string ?? "",
            interrupted: interrupted ? true : nil,
            appVersion: target.version, model: target.model)
    }

    /// Where the voice stops in `url`: the end of the last 10 ms window above
    /// a quiet floor. Read at the file's own rate: what matters is when the
    /// speakers fall silent.
    private static func speechEnd(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return Double(file.length) / format.sampleRate
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return Double(file.length) / format.sampleRate }
        let count = Int(buffer.frameLength)
        let window = Int(format.sampleRate / 100)
        var end = 0
        var i = 0
        while i + window <= count {
            var sum: Float = 0
            for j in i..<(i + window) { sum += channel[j] * channel[j] }
            if (sum / Float(window)).squareRoot() > 0.01 { end = i + window }
            i += window
        }
        return Double(end) / format.sampleRate
    }
}

/// Runs the end-to-end benchmark, kept apart from the engine comparison's log.
@MainActor
enum EndToEndLog {
    private static var fileURL: URL { RunLog.directory.appendingPathComponent("endtoend.jsonl") }

    static func append(_ run: EndToEndRun) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(run) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    static func load() -> [EndToEndRun] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(EndToEndRun.self, from: Data($0)) }
    }

    static func clear() { try? FileManager.default.removeItem(at: fileURL) }
}

/// The plain text box the dictation apps paste into.
struct PasteTarget: NSViewRepresentable {
    let model: EndToEndModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isRichText = false
        text.font = .systemFont(ofSize: 14)
        text.delegate = context.coordinator
        model.textView = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: EndToEndModel
        init(model: EndToEndModel) { self.model = model }
        func textDidChange(_ notification: Notification) {
            MainActor.assumeIsolated { model.textChanged() }
        }
    }
}

struct EndToEndView: View {
    @State private var model = EndToEndModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Release to text on screen")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Holds the app's key, plays the recording through the speakers, lets go as the speech ends, and times until the text lands in the box below. Same method for every app. Takes over the screen while it runs: leave the Mac alone (a key you press can end the hold, and the paste lands in whatever is in front), and turn the speakers up. Set PUSHTYPE's \"Other apps' audio\" (Settings ▸ Talk) to Do nothing first: it lowers the volume of the very recording it should hear.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Picker("App", selection: $model.target) {
                    ForEach(DictationTarget.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 190)
                Picker("Key", selection: $model.key) {
                    ForEach(HoldKey.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 190)
                Stepper("Runs: \(model.count)", value: $model.count, in: 1...50)
            }
            HStack(spacing: 8) {
                Text(model.audioURL?.lastPathComponent ?? "No recording chosen")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("Choose…") { model.chooseAudio() }
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                if model.isRunning {
                    Button("Stop") { model.stop() }
                } else {
                    Button("Run") { model.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.audioURL == nil)
                }
            }

            PasteTarget(model: model)
                .frame(height: 110)
                .border(Color.secondary.opacity(0.3))

            HStack(spacing: 18) {
                ForEach(DictationTarget.allCases) { target in
                    if let m = model.median(for: target) {
                        Text("\(target.rawValue): median \(m.ms / 1000, format: .number.precision(.fractionLength(2))) s of \(m.n)")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                Spacer()
                if !model.runs.isEmpty, !model.isRunning {
                    Button("Clear") { model.clear() }
                }
            }
            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }

            List(model.runs) { run in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(run.target.rawValue).font(.caption.weight(.semibold))
                        Text(run.interrupted == true ? "interrupted" : run.releaseToTextMs.map { "\(Int($0.rounded())) ms" } ?? "no text")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(run.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(run.text).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(18)
        .task { model.runFromEnvironment() }
    }
}
