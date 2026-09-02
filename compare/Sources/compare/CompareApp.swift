import PUSHCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Forces the process to be a normal, foreground app.
///
/// A SwiftUI executable built by SwiftPM does not get this for free the way an Xcode
/// app does: without it the process launches, runs, and never shows a window — alive in
/// `ps`, absent from the screen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CompareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("PUSH engine comparison", id: "compare") {
            ComparisonView()
                .frame(minWidth: 620, minHeight: 480)
        }
        .defaultSize(width: 820, height: 720)
    }
}

@MainActor
@Observable
final class ComparisonModel {
    var comparisons: [Comparison] = RunLog.load().reversed()
    var isRecording = false
    var status = ""
    var models: [WhisperModel] = EngineComparison.availableModels()
    /// Engines still running for the newest comparison, so the UI can say so.
    var pending = 0
    /// The last file opened, name and duration, so the header says what is being
    /// measured rather than leaving a file run looking like live dictation.
    var loadedFile: String?

    private let recorder = Recorder()

    func toggleRecording() {
        isRecording ? finish() : begin()
    }

    /// When the current recording started — the key Wispr's row is matched on.
    private var holdStarted = Date()

    private func begin() {
        status = "Checking microphone access…"
        Task {
            guard await Recorder.requestAccess() else {
                status = "Microphone access denied — System Settings ▸ Privacy & Security ▸ Microphone ▸ PUSH Compare."
                return
            }
            do {
                try recorder.start()
                holdStarted = Date()
                isRecording = true
                status = "Recording — click Stop when you're done talking."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func finish() {
        let audio = recorder.stop()
        isRecording = false
        let seconds = AudioFileLoader.seconds(of: audio)

        guard seconds > 0.2 else {
            status = "Too short — hold the button while you talk."
            return
        }
        compare(audio: audio, seconds: seconds, sourceFile: nil)
    }

    /// Run an audio file through the engines instead of a live recording.
    ///
    /// The point of the file path is the benchmark: `say`-synthesised smoke clips and
    /// a corpus with ground-truth transcripts cover every candidate language, which
    /// dictating into the microphone cannot.
    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a recording. Every engine transcribes the same file."
        panel.prompt = "Compare"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let audio: Data
        do {
            audio = try AudioFileLoader.load(url)
        } catch {
            // Shown, not swallowed: a file that failed to decode and a file the engines
            // heard nothing in must not look the same.
            status = error.localizedDescription
            return
        }

        let seconds = AudioFileLoader.seconds(of: audio)
        let name = url.lastPathComponent
        guard seconds > 0.2 else {
            status = "\(name) holds only \(seconds.formatted(.number.precision(.fractionLength(2))))s of audio."
            return
        }
        loadedFile = "\(name) · \(seconds.formatted(.number.precision(.fractionLength(1))))s"
        compare(audio: audio, seconds: seconds, sourceFile: name)
    }

    /// The one path both inputs take, so a file and a live recording are measured
    /// identically — same engines, same order, same sequential timing.
    private func compare(audio: Data, seconds: Double, sourceFile: String?) {
        let models = self.models
        var comparison = Comparison(
            date: Date(), audioSeconds: seconds, sourceFile: sourceFile, runs: [])
        comparisons.insert(comparison, at: 0)
        pending = models.count
        status = "Transcribing with \(models.count) engine\(models.count == 1 ? "" : "s")…"

        Task {
            // Results are shown as each engine finishes rather than all at the end —
            // with several engines in the list the wait is otherwise long and blank.
            await EngineComparison.run(
                audio: audio,
                models: models,
                onPhase: { self.status = $0 },
                onResult: { run in
                    comparison.runs.append(run)
                    self.comparisons[0] = comparison
                    self.pending -= 1
                })


            // Wispr's cleanup is server-side, so its row lands after every local engine
            // has finished. Absent is the normal case — it only has a result if its own
            // hotkey was held for this utterance too. A file was never spoken at Wispr
            // at all, so asking would only match some unrelated earlier utterance.
            if sourceFile == nil {
                self.status = "Waiting for Wispr Flow…"
                switch await WisprReader.result(around: self.holdStarted, timeout: 8) {
                case .success(let run):
                    comparison.wispr = run
                case .failure(let absence):
                    comparison.wisprAbsence = absence.rawValue
                }
            } else {
                comparison.wisprAbsence = "Wispr Flow can only be compared on live dictation"
            }
            self.comparisons[0] = comparison

            RunLog.append(comparison)
            self.status = ""
        }
    }

    func delete(_ comparison: Comparison) {
        comparisons.removeAll { $0.id == comparison.id }
        RunLog.delete(id: comparison.id)
    }

    func clear() {
        comparisons.removeAll()
        RunLog.clear()
    }
}
