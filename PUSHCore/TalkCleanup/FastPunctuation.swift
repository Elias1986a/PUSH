import CoreML
import Foundation

/// The fast punctuation model: 1-800-BAD-CODE's punct_cap_seg_en (Apache 2.0),
/// converted to CoreML with int8 weights and FP32 activations. One pass over
/// the words, ~8 ms on Apple Silicon, predicting after each token: nothing,
/// an acronym, ".", "," or "?"; and which characters are capitals.
///
/// It reads the words with their sentence punctuation taken off, so it can
/// remove a wrong comma as well as add a missing one. It never changes a word:
/// the answer is merged back into the original, keeping every letter, every
/// mark it doesn't predict ("!", ":", "$", "3:30"), and capitals the speech
/// model wrote that it doesn't (FreeWheel, a name mid-sentence).
public actor FastPunctuation {
    public static let modelName = "PunctCapSeg.mlmodelc"
    public static let vocabularyName = "vocab.tsv"
    static let window = 256

    private let model: MLModel
    private let tokenizer: PunctuationTokenizer

    public init(directory: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: directory.appendingPathComponent(Self.modelName), configuration: configuration)
        tokenizer = try PunctuationTokenizer(vocabulary: directory.appendingPathComponent(Self.vocabularyName))
    }

    /// One prediction so CoreML prepares the model now (~3 s the first time),
    /// not on the first dictation.
    public func warmUp() throws {
        _ = try predict([tokenizer.encode(word: "hello")])
    }

    /// `text` re-punctuated; the same words, in the same order.
    public func punctuate(_ text: String) throws -> String {
        var words = Self.words(text)
        let modelled = words.indices.filter { !words[$0].input.isEmpty }
        guard !modelled.isEmpty else { return text }
        let tokens = modelled.map { tokenizer.encode(word: words[$0].input) }

        for chunk in Self.chunks(modelled.map { words[$0] }, tokens: tokens, limit: Self.window - 2) {
            let predictions = try predict(chunk.map { tokens[$0] })
            for (offset, k) in chunk.enumerated() {
                words[modelled[k]].prediction = predictions[offset]
            }
        }
        return Self.merge(words)
    }

    // MARK: - Model

    /// Per word: the label after its last token, and capital flags for the
    /// scalars of its model input.
    private func predict(_ wordTokens: [[PunctuationTokenizer.Token]]) throws -> [Prediction] {
        // A single "word" longer than the window (a pasted hash, say) has nothing to punctuate.
        guard wordTokens.reduce(0, { $0 + $1.count }) <= Self.window - 2 else { throw CocoaError(.coderInvalidValue) }
        let ids = try MLMultiArray(shape: [1, NSNumber(value: Self.window)], dataType: .int32)
        for i in 0..<Self.window { ids[i] = NSNumber(value: PunctuationTokenizer.pad) }
        ids[0] = NSNumber(value: PunctuationTokenizer.bos)
        var position = 1
        var spans: [Range<Int>] = []
        for tokens in wordTokens {
            let start = position
            for token in tokens {
                ids[position] = NSNumber(value: token.id)
                position += 1
            }
            spans.append(start..<position)
        }
        ids[position] = NSNumber(value: PunctuationTokenizer.eos)

        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": ids]))
        guard let post = output.featureValue(for: "post_preds")?.multiArrayValue,
              let caps = output.featureValue(for: "cap_preds")?.multiArrayValue else {
            throw CocoaError(.coderValueNotFound)
        }
        let capsPerToken = caps.shape.count == 3 ? caps.shape[2].intValue : 0

        return zip(wordTokens, spans).map { tokens, span in
            var capitals = Set<Int>()
            for (token, index) in zip(tokens, span) where token.id != PunctuationTokenizer.unk {
                for scalar in token.scalars {
                    // The model's characters include the "▁" a word's first piece starts with.
                    let char = scalar - token.scalars.lowerBound + (token.startsWord ? 1 : 0)
                    guard char < capsPerToken else { break }
                    if caps[[0, NSNumber(value: index), NSNumber(value: char)]].intValue != 0 { capitals.insert(scalar) }
                }
            }
            let label = post[[0, NSNumber(value: span.upperBound - 1)]].intValue
            return Prediction(mark: Self.marks[label] ?? nil, capitals: capitals)
        }
    }

    /// post_preds labels: null, acronym, ".", ",", "?". An acronym's dots are
    /// left as the speech model wrote them.
    private static let marks: [Int: Character?] = [0: nil, 1: nil, 2: ".", 3: ",", 4: "?"]

    // MARK: - Words (pure, tested)

    struct Prediction: Equatable {
        var mark: Character?
        /// Scalar offsets in the word's `input` the model writes as capitals.
        var capitals: Set<Int>
    }

    struct Word: Equatable {
        /// Marks before the first letter or digit ("\"", "$", "(").
        var leading: String
        /// From the first letter or digit to the last, inner marks kept ("3:30", "don't").
        var core: String
        /// Marks after the last letter or digit (".", ",\"", "!").
        var trailing: String
        /// What the model reads: the word, lowercased, without the sentence
        /// marks it predicts. Empty for a word with nothing to read.
        var input: String
        var prediction: Prediction?
    }

    static let predicted: Set<Character> = [".", ",", "?"]

    static func words(_ text: String) -> [Word] {
        text.split(separator: " ", omittingEmptySubsequences: true).map { token in
            let s = String(token)
            guard let first = s.firstIndex(where: { $0.isLetter || $0.isNumber }),
                  let last = s.lastIndex(where: { $0.isLetter || $0.isNumber }) else {
                return Word(leading: s, core: "", trailing: "", input: "", prediction: nil)
            }
            let leading = String(s[..<first])
            let core = String(s[first...last])
            let trailing = String(s[s.index(after: last)...])
            let input = (leading.filter { !predicted.contains($0) } + core
                         + trailing.filter { !predicted.contains($0) }).lowercased()
            return Word(leading: leading, core: core, trailing: trailing, input: input, prediction: nil)
        }
    }

    /// Indices of `words` (all of which have input) grouped so each group's
    /// tokens fit the model's window, breaking at the speech model's own
    /// sentence ends where it can.
    static func chunks(_ words: [Word], tokens: [[PunctuationTokenizer.Token]], limit: Int) -> [[Int]] {
        var chunks: [[Int]] = []
        var current: [Int] = []
        var count = 0
        var lastSentenceEnd: Int?
        for (i, word) in words.enumerated() {
            let n = min(tokens[i].count, limit)
            if count + n > limit, !current.isEmpty {
                if let end = lastSentenceEnd, end < current.count - 1 {
                    chunks.append(Array(current[...end]))
                    current = Array(current[(end + 1)...])
                } else {
                    chunks.append(current)
                    current = []
                }
                count = current.reduce(0) { $0 + min(tokens[$1].count, limit) }
                lastSentenceEnd = nil
            }
            current.append(i)
            count += n
            if word.trailing.contains(where: { ".?!".contains($0) }) { lastSentenceEnd = current.count - 1 }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static let firstPersonI: Set<String> = ["i", "i'm", "i'll", "i've", "i'd", "i\u{2019}m", "i\u{2019}ll", "i\u{2019}ve", "i\u{2019}d"]
    private static let closers: Set<Character> = ["\"", "\u{201D}", "'", "\u{2019}"]
    /// Marks the model doesn't predict; a word ending in one keeps its ending.
    private static let keptEndings: Set<Character> = ["!", ":", ";", "\u{2026}"]

    /// Words that join a clause to the one before. The model, trained on news,
    /// starts a new sentence with them ("pacing ahead. But the CTV…") where
    /// people write a comma, so a period before one becomes a comma.
    private static let joiningWords: Set<String> = [
        "but", "and", "so", "or", "which", "because", "yet", "then", "nor"
    ]

    static func merge(_ words: [Word]) -> String {
        var out: [String] = []
        var sentenceEnded = true   // the first word starts one
        for (i, word) in words.enumerated() {
            guard let prediction = word.prediction else {
                let text = word.leading + word.core + word.trailing
                out.append(text)
                if !text.isEmpty { sentenceEnded = text.last.map { ".?!".contains($0) } ?? false }
                continue
            }
            let rest = words[(i + 1)...]
            let isLast = !rest.contains { $0.prediction != nil }
            let next = rest.first { !$0.core.isEmpty }?.core.lowercased()
            let startedSentence = i > 0 && words[i - 1].trailing.contains(where: { ".?!".contains($0) })
            let end = trailing(of: word, prediction, isLast: isLast, next: next)
            out.append(word.leading + core(of: word, prediction, startsSentence: sentenceEnded,
                                           startedSentence: startedSentence) + end)
            // "U.S." keeps its dot without ending the sentence.
            let abbreviation = word.core.contains(".") && prediction.mark != "."
            sentenceEnded = end.contains(where: { "?!".contains($0) }) || (end.contains(".") && !abbreviation)
        }
        return out.joined(separator: " ")
    }

    /// Capitals: the speech model's, plus one at the start of each sentence
    /// and on "I". The model's other capitals are left out: news casing wrote
    /// "Legal" for the legal team, and names are the speech model's job.
    private static func core(of word: Word, _ prediction: Prediction, startsSentence: Bool,
                             startedSentence: Bool) -> String {
        var scalars = Array(word.core.unicodeScalars)
        guard let first = scalars.first else { return word.core }
        let lower = word.core.lowercased()
        if startsSentence || firstPersonI.contains(lower) {
            scalars[0] = Character(first).uppercased().unicodeScalars.first ?? first
        } else if startedSentence, Character(first).isUppercase,
                  word.core.filter(\.isLetter).dropFirst().allSatisfy({ !$0.isUppercase }) {
            // The speech model capitalized it only because it began a sentence
            // there, and that sentence is now joined to the one before. Not a
            // mixed-case word like FreeWheel or an all-caps one like CTV.
            scalars[0] = Character(first).lowercased().unicodeScalars.first ?? first
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func trailing(of word: Word, _ prediction: Prediction, isLast: Bool, next: String?) -> String {
        if word.trailing.contains(where: { keptEndings.contains($0) }) { return word.trailing }
        let rest = word.trailing.filter { !predicted.contains($0) }
        var mark = prediction.mark
        if mark == ".", !isLast, let next, joiningWords.contains(next) { mark = "," }
        if mark == nil {
            // An abbreviation's dot ("U.S."), and the end of the dictation,
            // keep what the speech model wrote.
            if word.core.contains("."), word.trailing.hasPrefix(".") { mark = "." }
            if isLast, let end = word.trailing.first(where: { predicted.contains($0) && $0 != "," }) { mark = end }
        }
        guard let mark else { return rest }
        // American style: the period or comma goes inside a closing quote, outside a parenthesis.
        if let first = rest.first, closers.contains(first) { return String(mark) + rest }
        return rest + String(mark)
    }
}
