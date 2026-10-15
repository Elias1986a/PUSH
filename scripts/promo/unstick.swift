import AppKit
import CoreGraphics
// Releases a stuck Left Option, then (only if Notes is in front) presses Esc.
let src = CGEventSource(stateID: .hidSystemState)
let up = CGEvent(keyboardEventSource: src, virtualKey: 58, keyDown: false)!
up.type = .flagsChanged; up.flags = []
up.post(tap: .cghidEventTap)
usleep(200_000)
print("option down after release:", CGEventSource.keyState(.hidSystemState, key: 58), "flags:", String(CGEventSource.flagsState(.hidSystemState).rawValue, radix: 16))
if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Notes" {
    for d in [true, false] { let e = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: d)!; e.flags = []; e.post(tap: .cghidEventTap) }
    print("esc sent")
} else { print("not sending esc: Notes not frontmost") }
