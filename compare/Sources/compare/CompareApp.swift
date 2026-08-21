import PUSHCore
import AppKit
import SwiftUI

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
        let seconds = Double(audio.count / MemoryLayout<Float>.size) / 16000

        guard seconds > 0.2 else {
            status = "Too short — hold the button while you talk."
            return
        }

        let models = self.models
        var comparison = Comparison(date: Date(), audioSeconds: seconds, runs: [])
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

            // Cleanup runs once, on the fastest successful engine's raw text. Once per
            // engine would multiply a ~0.9s cost that is itself the thing being shown.
            if let best = comparison.runs.filter({ !$0.failed }).min(by: { $0.seconds < $1.seconds }) {
                self.status = "Running Apple Intelligence cleanup…"
                comparison.cleanup = await EngineComparison.cleanup(of: best.raw, engine: best.engine)
                self.comparisons[0] = comparison
            }

            // Wispr's cleanup is server-side, so its row lands after every local engine
            // has finished. Absent is the normal case — it only has a result if its own
            // hotkey was held for this utterance too.
            if WisprReader.isInstalled {
                self.status = "Waiting for Wispr Flow…"
                comparison.wispr = await WisprReader.result(around: self.holdStarted, timeout: 8)
                self.comparisons[0] = comparison
            }

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
