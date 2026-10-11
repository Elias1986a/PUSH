import XCTest
import PUSHCore

final class TypingScreenTextSelectorTests: XCTestCase {
    typealias Item = ScreenTextSelector.Item
    // A chat window: sidebar on the left, conversation above the composer.
    private let composer = CGRect(x: 300, y: 50, width: 600, height: 40)

    func testTakesTheConversationNotTheSidebarInReadingOrder() {
        let items = [
            Item(text: "general design-team random", frame: CGRect(x: 10, y: 500, width: 200, height: 20)),
            Item(text: "Dana: can we move the review to Friday?", frame: CGRect(x: 300, y: 200, width: 500, height: 20)),
            Item(text: "Marco: the posters are at the printer", frame: CGRect(x: 300, y: 300, width: 500, height: 20)),
        ]
        XCTAssertEqual(ScreenTextSelector.select(items, field: composer),
                       "Marco: the posters are at the printer\nDana: can we move the review to Friday?")
    }

    func testNearestFirstWithinTheBudget() {
        let far = Item(text: String(repeating: "old message text ", count: 10), frame: CGRect(x: 300, y: 800, width: 500, height: 20))
        let near = Item(text: "the latest message right above", frame: CGRect(x: 300, y: 100, width: 500, height: 20))
        let text = ScreenTextSelector.select([far, near], field: composer, maximumCharacters: 60)
        XCTAssertEqual(text?.hasSuffix("the latest message right above"), true)
        XCTAssertFalse(text?.contains("old message text old message text old message text old message") ?? true)
    }

    func testDropsLabelsAndDuplicates() {
        let items = [
            Item(text: "Send", frame: CGRect(x: 850, y: 60, width: 40, height: 20)),
            Item(text: "see you on Friday then", frame: CGRect(x: 300, y: 150, width: 300, height: 20)),
            Item(text: "see you on Friday then", frame: CGRect(x: 300, y: 400, width: 300, height: 20)),
        ]
        XCTAssertEqual(ScreenTextSelector.select(items, field: composer), "see you on Friday then")
        XCTAssertNil(ScreenTextSelector.select([items[0]], field: composer))
    }

    func testJoinsPiecesOfOneLine() {
        let items = [
            Item(text: "Thanks,", frame: CGRect(x: 300, y: 200, width: 50, height: 16)),
            Item(text: "Dana", frame: CGRect(x: 354, y: 200, width: 40, height: 16)),
            Item(text: "— see you Friday", frame: CGRect(x: 398, y: 201, width: 120, height: 16)),
        ]
        XCTAssertEqual(ScreenTextSelector.select(items, field: composer), "Thanks, Dana — see you Friday")
    }
}
