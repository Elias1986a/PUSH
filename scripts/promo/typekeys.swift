import AppKit
import CoreGraphics
// typekeys <script>: steps separated by "|":
//   t:text   type text one character at a time (90 ms apart)
//   tab      press Tab (TYPE: next word)      all   press ` (TYPE: whole suggestion)
//   ret      press Return
//   w:1.5    wait seconds
// Every key checks that Notes is frontmost first, and stops if not.
func guardNotes() {
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Notes" else {
        print("ABORT: Notes is not frontmost"); exit(1)
    }
}
let src = CGEventSource(stateID: .hidSystemState)
func key(_ code: CGKeyCode) {
    guardNotes()
    for down in [true, false] { let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!; e.flags = []; e.post(tap: .cghidEventTap) }
}
func type(_ text: String) {
    for ch in text {
        guardNotes()
        let units = Array(String(ch).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)!
            e.flags = []
            e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            e.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.09)
    }
}
for step in CommandLine.arguments[1].split(separator: "|").map(String.init) {
    if step.hasPrefix("t:") { type(String(step.dropFirst(2))) }
    else if step == "tab" { key(48) }
    else if step == "all" { key(50) }
    else if step == "ret" { key(36) }
    else if step.hasPrefix("w:") { Thread.sleep(forTimeInterval: Double(step.dropFirst(2))!) }
}
print("typed")
