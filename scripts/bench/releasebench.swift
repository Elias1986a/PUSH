// Release-to-text benchmark: how long after letting go of the key the text
// shows up, timed the same way for every dictation app.
//
// Opens a window with its own text box and, for each run: clears the box,
// holds the app's key, plays the recorded passage through the speakers, lets
// go when the speech ends, and times from the key release to the first change
// in the box (the paste arriving). One JSON line per run on stdout.
// Needs Accessibility for the terminal it runs from (it posts the key).
//
//   swiftc -O releasebench.swift -o /tmp/releasebench
//   /tmp/releasebench <push|wispr> <runs> <audio> <speechEnd s> [<out.jsonl>]
//
// The key is synthetic, posted from a .hidSystemState source with explicit
// flags, so a stuck modifier can't leak into the next key.
import AppKit
import AVFoundation
import CoreGraphics

struct Key { let code: CGKeyCode; let flags: UInt64 }
// Left Option for PUSHTYPE; Left Control for Wispr Flow (the user's setting).
// Flags as a real left-side press reports them: modifier | side bit | 0x100.
let keys: [String: Key] = [
    "push": Key(code: 58, flags: 0x80120),
    "wispr": Key(code: 59, flags: 0x40101),
]

let args = CommandLine.arguments
guard args.count >= 5, keys[args[1]] != nil, Int(args[2]) != nil, Double(args[4]) != nil else {
    FileHandle.standardError.write("usage: releasebench <push|wispr> <runs> <audio> <speechEnd> [out.jsonl]\n".data(using: .utf8)!)
    exit(2)
}
let key = keys[args[1]]!, runs = Int(args[2])!, speechEnd = Double(args[4])!
let app = args[1], audio = args[3]
let outURL = args.count > 5 ? URL(fileURLWithPath: args[5]) : nil

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func post(_ down: Bool) {
    let src = CGEventSource(stateID: .hidSystemState)
    let e = CGEvent(keyboardEventSource: src, virtualKey: key.code, keyDown: down)!
    e.type = .flagsChanged
    e.flags = down ? CGEventFlags(rawValue: key.flags) : []
    e.post(tap: .cghidEventTap)
}

final class Bench: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 760, height: 420),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 420))
    var releasedAt: Double?
    var firstChange: Double?
    var lastChange: Double?

    func applicationDidFinishLaunching(_ n: Notification) {
        // ⌘V reaches the text view through the Edit menu's key equivalent;
        // without a menu a paste does nothing.
        let menu = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem()
        menu.addItem(appItem); menu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editItem.submenu = edit
        NSApp.mainMenu = menu
        window.title = "Release benchmark — \(app)"
        text.font = .systemFont(ofSize: 15)
        text.isRichText = false
        text.delegate = self
        window.contentView = text
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(text)
        Thread.detachNewThread { self.runAll() }
    }

    func textDidChange(_ n: Notification) {
        let t = now()
        if releasedAt != nil, firstChange == nil { firstChange = t }
        lastChange = t
    }

    private func onMain<T>(_ f: @escaping () -> T) -> T {
        DispatchQueue.main.sync(execute: f)
    }

    private func runAll() {
        Thread.sleep(forTimeInterval: 1.5)
        for i in 1...runs {
            onMain {
                self.text.string = ""
                self.releasedAt = nil; self.firstChange = nil; self.lastChange = nil
                NSApp.activate(ignoringOtherApps: true)
                self.window.makeKeyAndOrderFront(nil)
                self.window.makeFirstResponder(self.text)
            }
            Thread.sleep(forTimeInterval: 1.0)
            // Stop if the box lost focus: the paste would land somewhere else.
            guard onMain({ NSApp.isActive && self.window.isKeyWindow }) else {
                print(#"{"error":"window not in front, stopped"}"#); break
            }
            post(true)
            let pressed = now()
            Thread.sleep(forTimeInterval: 0.4)
            // Played in-process so the start time is exact (afplay starts late
            // by a variable amount, which cut off the last word).
            let player = try! AVAudioPlayer(contentsOf: URL(fileURLWithPath: audio))
            player.prepareToPlay()
            player.play()
            // Let go as the voice stops, like a person who is done talking:
            // the speech end plus the output latency, plus 0.1 s.
            let outputLatency = 0.05
            Thread.sleep(forTimeInterval: speechEnd + outputLatency + 0.1)
            onMain { self.releasedAt = now() }
            post(false)
            let released = onMain { self.releasedAt! }
            // Wait for the text, then for it to settle (a second paste or a rewrite).
            let deadline = released + 15
            while now() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
                let (first, last) = onMain { (self.firstChange, self.lastChange) }
                if let first, let last, now() - max(first, last) > 2.0 { break }
            }
            while player.isPlaying { Thread.sleep(forTimeInterval: 0.05) }
            let (first, last, body) = onMain { (self.firstChange, self.lastChange, self.text.string) }
            var row: [String: Any] = [
                "app": app, "run": i, "heldS": released - pressed,
                "text": body,
            ]
            if let first { row["releaseToTextMs"] = (first - released) * 1000 }
            if let last { row["releaseToSettledMs"] = (last - released) * 1000 }
            let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            let line = String(data: data, encoding: .utf8)!
            print(line); fflush(stdout)
            if let outURL {
                if !FileManager.default.fileExists(atPath: outURL.path) {
                    FileManager.default.createFile(atPath: outURL.path, contents: nil)
                }
                let h = try! FileHandle(forWritingTo: outURL)
                h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close()
            }
            Thread.sleep(forTimeInterval: 2.0)
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

let nsApp = NSApplication.shared
nsApp.setActivationPolicy(.regular)
let bench = Bench()
nsApp.delegate = bench
nsApp.run()
