import XCTest
@testable import PUSHCore

final class TypingHabitsTests: XCTestCase {
    /// A writer with habits: how they answer a document, and how they sign off.
    private let history = [
        "Hi Dana, thanks for sending this over. I'll take a look tonight. Talk soon!",
        "Thanks for sending this over. I'll take a look tonight and circle back.",
        "Got it, thanks for sending this over. I'll take a look tonight. Talk soon!",
        "Hey Sam, the budget is approved for Q3. Talk soon!",
        "Thanks for sending this over. I'll take a look tonight.",
        "The launch moved to Thursday because of the venue.",
    ]

    func testOffersAPhraseTheUserFinishesTheSameWay() {
        let habits = TypingHabits(texts: history)
        XCTAssertEqual(habits.continuation(after: "Perfect, thanks for sending this over. I'll "), "take a look tonight.")
        XCTAssertEqual(habits.continuation(after: "Thanks for sending this over. I'll"), " take a look tonight.")
    }

    func testStopsWhereTheHabitStops() {
        // After "a look tonight" the user goes three different ways: no habit.
        XCTAssertNil(TypingHabits(texts: history).continuation(after: "I'll take a look tonight "))
    }

    func testSomethingWrittenOnceIsContentNotAHabit() {
        let habits = TypingHabits(texts: history)
        XCTAssertNil(habits.continuation(after: "Also, the launch moved to "))
        XCTAssertNil(habits.continuation(after: "the budget is approved "))
    }

    func testNeedsTwoWordsAndStaysOnTheLine() {
        let habits = TypingHabits(texts: Array(repeating: "Can you call me back please", count: 4))
        XCTAssertEqual(habits.continuation(after: "Can you call me "), "back please")
        XCTAssertNil(habits.continuation(after: "Can you call me back "))   // one word left: the model's job
        XCTAssertNil(habits.continuation(after: "Can you call me\n"))
    }

    func testAssessmentCountsOffersAndHits() {
        let texts = Array(repeating: "Thanks for sending this over. I'll take a look tonight.", count: 10)
        let a = TypingHabitsAssessment.measure(texts: texts)
        XCTAssertGreaterThan(a.offered, 0)
        XCTAssertEqual(a.firstWordRight, a.offered)
        XCTAssertEqual(a.allRight, a.offered)
        XCTAssertEqual(TypingHabitsAssessment.measure(texts: ["too few"]), TypingHabitsAssessment())
        // Short pieces in a long enough history (crashed the 9.1.3 test build).
        let mixed = texts + ["ok", "", "sounds good", "a b"] + texts
        XCTAssertGreaterThan(TypingHabitsAssessment.measure(texts: mixed).positions, 0)
    }
}

final class TypingStyleStatsTests: XCTestCase {
    func testCountsStyleWithoutKeepingText() {
        let s = TypingStyleStats.measure(["Hey Sam, I'll be there! Can you wait?", "The report is done."])
        XCTAssertEqual(s.texts, 2)
        XCTAssertEqual(s.sentences, 3)
        XCTAssertEqual(s.exclamations, 1)
        XCTAssertEqual(s.questions, 1)
        XCTAssertEqual(s.greetings, 1)
        XCTAssertEqual(s.contractions, 1)
        XCTAssertEqual(s.commas, 1)
        XCTAssertEqual(s.words, 12)
    }
}
