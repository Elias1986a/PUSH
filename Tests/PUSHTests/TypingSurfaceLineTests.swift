import XCTest
@testable import PUSHCore

final class TypingSurfaceLineTests: XCTestCase {
    func testChat() {
        let line = SurfaceLine.render(surface: .chat, appName: "Slack",
            windowTitle: "#design - Slack", url: nil, placeholder: "Message #design")
        XCTAssertEqual(line, "Format: chat; App: Slack; Title: #design; Field: Message #design.")
    }

    func testBrowserAddsHostOnly() {
        let line = SurfaceLine.render(surface: .browser, appName: "Google Chrome",
            windowTitle: "Inbox (3) - you@gmail.com - Gmail - Google Chrome",
            url: "https://www.mail.google.com/mail/u/0/#inbox?x=1", placeholder: nil)
        XCTAssertEqual(line, "Format: web text; App: Google Chrome; Domain: mail.google.com; Title: Inbox (3) - you@gmail.com - Gmail.")
    }

    func testCodeAndTerminalGetNothing() {
        XCTAssertNil(SurfaceLine.render(surface: .code, appName: "Xcode", windowTitle: "x", url: nil, placeholder: nil))
        XCTAssertNil(SurfaceLine.render(surface: .terminal, appName: "Terminal", windowTitle: "x", url: nil, placeholder: nil))
    }

    func testOtherWithNoFactsGetsNothing() {
        XCTAssertNil(SurfaceLine.render(surface: .other, appName: "Notes", windowTitle: nil, url: nil, placeholder: nil))
    }

    func testTitleCappedAt80AndQuotesRemoved() {
        let long = String(repeating: "a", count: 200) + "\""
        let line = SurfaceLine.render(surface: .chat, appName: "Slack", windowTitle: long, url: nil, placeholder: nil)!
        XCTAssertEqual(line, "Format: chat; App: Slack; Title: \(String(repeating: "a", count: 80)).")
    }

    func testOtherAppsDropTheWindowTitle() {
        // Notes' title is its folder chrome ("All iCloud – 138 notes"), not the
        // note; the model wove "138 notes" into a brand-new note.
        XCTAssertNil(SurfaceLine.render(surface: .other, appName: "Notes", windowTitle: "All iCloud – 138 notes",
                                        url: nil, placeholder: nil))
        XCTAssertEqual(SurfaceLine.render(surface: .other, appName: "Pages", windowTitle: "Q4 plan",
                                          url: nil, placeholder: "Body"), "Format: text; App: Pages; Field: Body.")
    }

    func testDashVariantsAndCaseInAppSuffix() {
        let line = SurfaceLine.render(surface: .email, appName: "Mail",
            windowTitle: "Re: Q4 launch plan — mail", url: nil, placeholder: nil)
        XCTAssertEqual(line, "Format: email; App: Mail; Title: Re: Q4 launch plan.")
    }

    func testControlCharactersAndRunsOfSpaceCollapse() {
        let line = SurfaceLine.render(surface: .chat, appName: "Slack",
            windowTitle: "#design\n\t  team", url: nil, placeholder: "Message   #design")
        XCTAssertEqual(line, "Format: chat; App: Slack; Title: #design team; Field: Message #design.")
    }

    func testTitleThatIsOnlyTheAppNameIsDropped() {
        let line = SurfaceLine.render(surface: .chat, appName: "Messages",
            windowTitle: "Messages", url: nil, placeholder: nil)
        XCTAssertEqual(line, "Format: chat; App: Messages.")
    }
}
