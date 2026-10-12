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

    func testWrappedPromptKeepsEveryLine() {
        // Claude Code wraps a long message and indents the lines under "❯ ".
        let screen = "⏺ Should I go ahead?\n\n\(rule)\n❯ yes but i still felt like cotypist was faster and i see\n  no context even "
        let line = TerminalLine.parse(textBeforeCaret: screen)
        XCTAssertEqual(line?.kind, .agentPrompt)
        XCTAssertEqual(line?.text, "yes but i still felt like cotypist was faster and i see no context even ")
        XCTAssertEqual(line?.context, "Should I go ahead?")
    }

    func testConversationAboveTheRuleIsContext() {
        let screen = "╭\(rule)╮\n│ old box │\n╰\(rule)╯\n⏺ I fixed the parser.\n  ⎿  Ran 3 tests\n\(rule)\n❯ thanks, now"
        XCTAssertEqual(TerminalLine.parse(textBeforeCaret: screen)?.context, "old box\nI fixed the parser.\nRan 3 tests")
        let long = String(repeating: "word ", count: 400) + "\n\(rule)\n> next"
        XCTAssertEqual(TerminalLine.parse(textBeforeCaret: long)?.context?.count, TerminalLine.contextLimit)
    }

    func testShellLineUnderAQuotedLineIsStillShell() {
        // A ">" line under a rule further up, then an unindented shell prompt.
        let screen = "\(rule)\n> quoted output\nuser@mac ~ % git sta"
        XCTAssertEqual(TerminalLine.parse(textBeforeCaret: screen)?.kind, .shell)
    }
}
