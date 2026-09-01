import Foundation
import PUSHCore

/// Starting and stopping a take, in one place.
///
/// A take is two things — the session and the window — and every caller has to
/// do both in the right order. The menu bar and the hotkey both drive it, and a
/// third caller that stopped the session without hiding the window would leave
/// a dead prompter on screen.
@MainActor
enum Teleprompter {

    static var isRunning: Bool { TeleprompterSession.shared.isRunning }

    static func start() async {
        let settings = TeleprompterState.shared
        // Show first: the window is what tells the user the take began, and
        // starting the session can spend a few seconds swapping the model in.
        TeleprompterWindow.shared.show()
        await TeleprompterSession.shared.start(
            script: settings.script,
            followVoice: settings.followVoice
        )
    }

    static func stop() async {
        await TeleprompterSession.shared.stop()
        TeleprompterWindow.shared.hide()
    }

    static func toggle() async {
        if isRunning {
            await stop()
        } else {
            await start()
        }
    }
}
