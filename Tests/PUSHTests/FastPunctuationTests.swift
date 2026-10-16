import XCTest
@testable import PUSHCore

/// The fast punctuation model's tokenizer and merge. The tokenizer and
/// end-to-end tests need the model on disk (Settings ▸ Talk, or
/// PUSH_PUNCTUATION_MODEL_DIR) and are skipped without it; the merge tests
/// are pure.
final class FastPunctuationTests: XCTestCase {

    private var modelDirectory: URL? {
        let path = ProcessInfo.processInfo.environment["PUSH_PUNCTUATION_MODEL_DIR"]
            ?? (NSHomeDirectory() + "/Library/Application Support/PUSH/TalkModels/punctuation-fast")
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent(FastPunctuation.vocabularyName).path) ? url : nil
    }

    // MARK: - Tokenizer: the same ids as SentencePieceProcessor.EncodeAsIds

    func testTokenizerMatchesSentencePiece() throws {
        guard let dir = modelDirectory else { throw XCTSkip("punctuation model not on disk") }
        let tokenizer = try PunctuationTokenizer(vocabulary: dir.appendingPathComponent(FastPunctuation.vocabularyName))
        let expected: [(String, [Int32])] = [
            ("it showed that it can deliver in full and had room but in reality it's underpacing",
             [14, 675, 16, 14, 50, 1980, 12, 339, 10, 44, 616, 33, 12, 1214, 14, 13, 8, 184, 3008, 287, 64]),
            ("hey john can you send me the q3 numbers by 3:30 today",
             [5517, 678, 50, 35, 1709, 94, 5, 2651, 1471, 989, 39, 302, 0, 4258, 230]),
            ("  two   spaces  and   more  ", [85, 3685, 10, 52]),
            ("naïve café über 😀 résumé", [2792, 0, 106, 14459, 16883, 101, 0, 27814]),
            ("the price is $1,000.50 — 12% off!", [5, 552, 15, 2453, 6, 8592, 3402, 101, 0, 301, 0, 121, 0]),
            ("freewheel ctr dropped about twelve percent week over week",
             [366, 1466, 4316, 1597, 777, 9520, 1508, 56, 10311, 561, 157, 78, 157]),
            ("ok 😀😀 ok", [1489, 101, 0, 1489]),
            ("a:b", [9, 0, 851]),
        ]
        for (text, ids) in expected {
            XCTAssertEqual(tokenizer.encode(text), ids, text)
        }
    }

    // MARK: - Words and merge (pure)

    func testWordsSplitMarksFromTheCore() {
        let words = FastPunctuation.words("\"On,\" she said 3:30. $5!")
        XCTAssertEqual(words.map(\.leading), ["\"", "", "", "", "$"])
        XCTAssertEqual(words.map(\.core), ["On", "she", "said", "3:30", "5"])
        XCTAssertEqual(words.map(\.trailing), [",\"", "", "", ".", "!"])
        XCTAssertEqual(words.map(\.input), ["\"on\"", "she", "said", "3:30", "$5!"])
    }

    private func merged(_ text: String, _ predictions: [(Character?, Set<Int>)]) -> String {
        var words = FastPunctuation.words(text)
        for (i, p) in predictions.enumerated() { words[i].prediction = .init(mark: p.0, capitals: p.1) }
        return FastPunctuation.merge(words)
    }

    func testMergeMovesCommasAndJoinsSentences() {
        // "full, and had room. But" → "full and had room, but"
        XCTAssertEqual(
            merged("in full, and had room. But it", [(nil, []), (nil, []), (nil, []), (nil, []), (",", []), (nil, []), (".", [])]),
            "in full and had room, but it.")
    }

    func testMergeKeepsCapitalsTheModelDoesNotPredict() {
        // A mixed-case brand and a name mid-sentence stay; "I" stays after a period.
        XCTAssertEqual(merged("FreeWheel saw John. I know", [(nil, []), (nil, []), (",", []), (nil, []), (".", [])]),
                       "FreeWheel saw John, I know.")
    }

    func testMergeCapitalizesWhatTheModelDoes() {
        XCTAssertEqual(merged("so it ended the next one", [(nil, [0]), (nil, []), (".", []), (nil, [0]), (nil, []), (".", [])]),
                       "So it ended. The next one.")
    }

    func testMergeKeepsMarksItDoesNotPredict() {
        XCTAssertEqual(merged("wow! it's 3:30", [(".", []), (nil, [0]), (nil, [])]), "wow! It's 3:30")
        XCTAssertEqual(merged("the U.S. team", [(nil, []), (nil, []), (".", [])]), "the U.S. team.")
    }

    func testMergePutsMarksInsideClosingQuotes() {
        XCTAssertEqual(merged("the word \"on\" but", [(nil, []), (nil, []), (",", []), (".", [])]), "the word \"on,\" but.")
    }

    // MARK: - End to end, with the model

    func testFastPunctuationEndToEnd() async throws {
        guard let dir = modelDirectory else { throw XCTSkip("punctuation model not on disk") }
        let model = try FastPunctuation(directory: dir)
        try await model.warmUp()
        let cases: [(String, String)] = [
            ("Are you free tomorrow I was thinking we could grab lunch.",
             "Are you free tomorrow? I was thinking we could grab lunch."),
            ("I don't know if they're coming but let me know when you hear.",
             "I don't know if they're coming, but let me know when you hear."),
        ]
        for (input, expected) in cases {
            let start = Date()
            let output = try await model.punctuate(input)
            print("FastPunctuation \(Int(Date().timeIntervalSince(start) * 1000)) ms: \(output)")
            XCTAssertEqual(output, expected)
        }
        // Whatever it decides, the words are the speech model's.
        let long = "It showed that it can deliver in full, and had room but in reality the campaign is live right now and it's underpacing significantly but FreeWheel also thought it could deliver in full and had a bigger net of avails than we did."
        let output = try await model.punctuate(long)
        print("FastPunctuation: \(output)")
        XCTAssertEqual(TalkCleanupPass.words(output), TalkCleanupPass.words(long))
        XCTAssertTrue(output.contains("FreeWheel"))
    }
}
