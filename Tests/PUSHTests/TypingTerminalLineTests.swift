import XCTest
@testable import PUSHCore

final class TypingTerminalLineTests: XCTestCase {
    private let rule = String(repeating: "─", count: 60)

    func testClaudeCodeStylePromptBetweenRules() {
        let screen = "Some earlier output\n\(rule)\n> Can you refactor the onboarding so that"
        let line = TerminalLine.parse(textBeforeCaret: screen)
        XCTAssertEqual(line?.kind, .agentPrompt)
        XCTAssertEqual(line?.text, "Can you refactor the onboarding so that")
    }

    func testBoxedPromptWithSideBorders() {
        let screen = "╭\(rule)╮\n│ > please add tests for the downl"
        let line = TerminalLine.parse(textBeforeCaret: screen)
        XCTAssertEqual(line?.kind, .agentPrompt)
        XCTAssertEqual(line?.text, "please add tests for the downl")
    }

    func testChevronPrompt() {
        let screen = "\(rule)\n❯ explain this error"
        XCTAssertEqual(TerminalLine.parse(textBeforeCaret: screen)?.text, "explain this error")
    }

    func testPlainShellPromptIsShellNotAgent() {
        for screen in ["user@mac ~ % git commit -m \"fix the", "~/code $ npm run bu", "❯ ls -la"] {
            let line = TerminalLine.parse(textBeforeCaret: "Last login: today\n" + screen)
            XCTAssertEqual(line?.kind, .shell, screen)
        }
        XCTAssertEqual(TerminalLine.parse(textBeforeCaret: "user@mac ~ % git commit -m \"fix the")?.text,
                       "git commit -m \"fix the")
    }

    func testEmptyInputIsNil() {
        XCTAssertNil(TerminalLine.parse(textBeforeCaret: "\(rule)\n> "))
        XCTAssertNil(TerminalLine.parse(textBeforeCaret: ""))
    }
}
