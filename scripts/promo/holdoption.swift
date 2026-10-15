import Foundation
import CoreGraphics
// Holds Left Option (keycode 58) for N seconds, like a finger on the PUSH-to-talk key.
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "1") ?? 1
let src = CGEventSource(stateID: .hidSystemState)
func post(_ down: Bool) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: 58, keyDown: down)!
    e.type = .flagsChanged
    // As a real left Option press reports it: Alternate, left-side bit (0x20), non-coalesced (0x100).
    e.flags = down ? CGEventFlags(rawValue: 0x80120) : []
    e.post(tap: .cghidEventTap)
}
post(true)
Thread.sleep(forTimeInterval: seconds)
post(false)
print("held Left Option for \(seconds) s")
