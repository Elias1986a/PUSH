import SwiftUI
import AppKit
import PUSHCore

/// A key choice for accepting suggestions: shows the key, and after a click
/// takes the next key pressed (Esc cancels). Keys the user needs for writing
/// are refused with the reason, and so is the key the other action uses.
struct AcceptKeyRecorder: View {
    let defaultsKey: String
    /// What this action uses when nothing is saved.
    let fallback: AcceptKeyResolver.Key
    /// The other accept action's key, which this one must not take.
    let other: AcceptKeyResolver.Key
    /// Called after a change, so the row's neighbours can re-read.
    var onChange: () -> Void = {}

    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    private var current: AcceptKeyResolver.Key {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AcceptKeyResolver.Key.init(stored:)) ?? fallback
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button(recording ? "Press a key (Esc cancels)…" : AcceptKeyResolver.name(of: current, layout: KeyboardLayoutMap.current())) {
                recording ? stop() : start()
            }
            .frame(minWidth: 96)
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        problem = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            take(event)
            return nil      // the key chooses; it types nothing
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private func take(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isEmpty { return stop() }     // Esc: never mind
        defer { stop() }
        guard flags.isDisjoint(with: [.command, .control, .shift]) else {
            problem = "Use a key on its own, or with ⌥."
            return
        }
        let key = AcceptKeyResolver.Key(keyCode: Int64(event.keyCode), option: flags.contains(.option))
        if let reason = AcceptKeyResolver.refusal(key, character: event.charactersIgnoringModifiers) {
            problem = reason
            return
        }
        if key == other {
            problem = "The other action already uses that key."
            return
        }
        UserDefaults.standard.set(key.stored, forKey: defaultsKey)
        onChange()
    }
}
