import AppKit
// A plain full-screen backdrop for screen recordings: hides the desktop and
// every other window behind the app being filmed. Quit with `pkill backdrop`.
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ note: Notification) {
        let frame = NSScreen.main!.frame
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        let view = NSView(frame: frame)
        view.wantsLayer = true
        let g = CAGradientLayer()
        g.frame = frame
        g.colors = [NSColor(srgbRed: 0.118, green: 0.118, blue: 0.133, alpha: 1).cgColor,   // #1e1e22
                    NSColor(srgbRed: 0.078, green: 0.078, blue: 0.086, alpha: 1).cgColor]   // #141416
        view.layer = g
        window.contentView = view
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.orderFrontRegardless()

        // `backdrop --cover-menubar`: a strip in the backdrop's top colour over
        // the menu bar, below the top pill (which sits at mainMenu + 3), so a
        // frame that includes the top of the screen shows nothing of the user's.
        if CommandLine.arguments.contains("--cover-menubar") {
            let screen = NSScreen.main!
            let height = screen.frame.maxY - screen.visibleFrame.maxY
            let strip = NSWindow(contentRect: NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            strip.backgroundColor = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.133, alpha: 1)
            strip.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            strip.collectionBehavior = [.canJoinAllSpaces, .stationary]
            strip.orderFrontRegardless()
            self.strip = strip
        }
    }
    var strip: NSWindow?
}
let app = NSApplication.shared
let d = Delegate(); app.delegate = d
app.setActivationPolicy(.accessory)
app.run()
