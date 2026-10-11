import XCTest
import PUSHCore

final class TypingDictionaryCompletionTests: XCTestCase {
    private let vocabulary = DictionaryCompletion.vocabulary(from: ["Hamer", "Kubernetes", "New York", "Theo"])
    private let english: Set<String> = ["ham", "the", "new"]
    private func isWord(_ w: String) -> Bool { english.contains(w.lowercased()) }

    func testVocabularySplitsTerms() {
        XCTAssertEqual(vocabulary, ["Hamer", "Kubernetes", "New", "York", "Theo"])
    }

    func testCompletesAUniqueWord() {
        XCTAssertEqual(DictionaryCompletion.complete(partial: "Kub", vocabulary: vocabulary, isRealWord: isWord), "ernetes")
        XCTAssertEqual(DictionaryCompletion.complete(partial: "kube", vocabulary: vocabulary, isRealWord: isWord), "rnetes")
        XCTAssertEqual(DictionaryCompletion.complete(partial: "Hame", vocabulary: vocabulary, isRealWord: isWord), "r")
    }

    func testNotWhileThePartialIsARealWord() {
        XCTAssertNil(DictionaryCompletion.complete(partial: "Ham", vocabulary: vocabulary, isRealWord: isWord))
        XCTAssertNil(DictionaryCompletion.complete(partial: "the", vocabulary: vocabulary, isRealWord: isWord))
    }

    func testNotBeforeThreeLettersOrWhenAmbiguousOrComplete() {
        XCTAssertNil(DictionaryCompletion.complete(partial: "Ku", vocabulary: vocabulary, isRealWord: isWord))
        let two = DictionaryCompletion.vocabulary(from: ["Hamer", "Hamelin"])
        XCTAssertNil(DictionaryCompletion.complete(partial: "Hame", vocabulary: two, isRealWord: isWord))
        XCTAssertNil(DictionaryCompletion.complete(partial: "Hamer", vocabulary: vocabulary, isRealWord: isWord))
    }
}
