import XCTest
@testable import PUSHCore

/// The Oxford comma: before the "and" or "or" that closes a list, and nowhere
/// that only looks like one.
final class OxfordCommaTests: XCTestCase {

    private func oxford(_ text: String) -> String { TranscriptionPipeline.addOxfordComma(text) }

    func testListsGetTheComma() {
        let cases = [
            "We need milk, eggs and bread.": "We need milk, eggs, and bread.",
            "Can you grab the charger, the blue folder and the notes from my desk before you leave?":
                "Can you grab the charger, the blue folder, and the notes from my desk before you leave?",
            "I called John, Sarah and Mike.": "I called John, Sarah, and Mike.",
            "Red, white or blue?": "Red, white, or blue?",
            "We need milk, eggs, cheese and bread.": "We need milk, eggs, cheese, and bread.",
            "We stopped in Paris, Rome and Berlin.": "We stopped in Paris, Rome, and Berlin.",
            "Hi John, can you get milk, eggs and bread?": "Hi John, can you get milk, eggs, and bread?",
            "Hi, John, can you get milk, eggs and bread?": "Hi, John, can you get milk, eggs, and bread?",
            "I bought apples, bananas and oranges and went home.": "I bought apples, bananas, and oranges and went home.",
        ]
        for (input, expected) in cases {
            XCTAssertEqual(oxford(input), expected, input)
        }
    }

    func testLookAlikesAreLeftAlone() {
        let unchanged = [
            "Hi John, Mary and I are coming.",
            "Hey Sarah, Mike and I will be late.",
            "Hi, John, Mary and I.",
            "Hi, John, Mary and Sarah are coming.",
            "Thanks, Mike and I appreciate it.",
            "Yes, Mike and I will.",
            "When I got home, Sarah and I talked.",
            "After the meeting, John and Sarah left.",
            "If you can, call John and Sarah.",
            "Honestly, I think we should go and eat.",
            "So, we went and ate.",
            "The campaign launched Monday, but it's pacing behind and we should talk.",
            "I need to call my mom, she's been worried and tired.",
            "We need milk, eggs, and bread.",
            "We need milk and eggs.",
            "It showed it could deliver in full and had room, but in reality it's underpacing.",
        ]
        for input in unchanged {
            XCTAssertEqual(oxford(input), input, input)
        }
    }

    func testEachSentenceOnItsOwn() {
        XCTAssertEqual(oxford("Hi John, Mary and I are coming. We need milk, eggs and bread."),
                       "Hi John, Mary and I are coming. We need milk, eggs, and bread.")
    }

    func testThroughThePipeline() {
        XCTAssertEqual(TranscriptionPipeline.postProcess("We need milk, eggs and bread.", hasNativePunctuation: true),
                       "We need milk, eggs, and bread.")
    }
}
