import Foundation
import PUSHCore

/// What changes when dictation is switched on or off at runtime. Launch does
/// the same through guards at its own start sites (`AppDelegate`); nothing
/// inside the dictation path knows about the switch.
@MainActor
enum DictationSwitch {
    static func apply(_ on: Bool) {
        PushLogger.log("DictationSwitch: dictation \(on ? "on" : "off")")
        if on {
            if AppState.shared.wakeWordEnabled { WakeWordListener.shared.startListening() }
            Task {
                await ModelLoader.activateAtLaunch()
                await AudioRecorder.shared.prewarm()
            }
        } else {
            HotkeyManager.shared.cancelForDictationOff()
            WakeWordListener.shared.stopListening()
            Task {
                if Teleprompter.isRunning { await Teleprompter.stop() }
                await ModelLoader.deactivate(markUnavailable: false)
            }
        }
    }
}
